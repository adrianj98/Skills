export const meta = {
  name: 'review',
  description: 'Attack a diff from several independent lenses, then refute the findings before reporting',
  whenToUse: 'After generating or receiving a non-trivial diff you are about to trust. Works in any repo.',
  phases: [
    { title: 'Scope', detail: 'resolve the diff range and split it into review units' },
    { title: 'Attack', detail: 'independent adversaries per unit, one per lens' },
    { title: 'Verify', detail: 'refuters try to kill each finding' },
    { title: 'Report', detail: 'survivors only' },
  ],
}

// args: { range?: string, lenses?: string[], refuters?: number, threshold?: number }
const cfg = args || {}
const RANGE = cfg.range || ''
const REFUTERS = cfg.refuters || 3
const THRESHOLD = cfg.threshold || 2 // survivors need this many non-refuting votes

const LENSES = cfg.lenses || [
  { key: 'correctness', focus: 'evaluation order, boundaries, off-by-one, sign and overflow, empty/null/zero cases, and logic that is subtly not what the surrounding code expects' },
  { key: 'failure-paths', focus: 'error branches, cleanup and teardown, early returns, partial failure leaving inconsistent state, swallowed or defaulted errors' },
  { key: 'lifetime-and-async', focus: 'resource ownership and lifetime, use-after-free / use-after-close, races, unawaited work, cancellation, retries that duplicate side effects' },
  { key: 'contract-drift', focus: 'changed types, nullability, thrown errors or return shapes that callers OUTSIDE this diff still expect the old version of — grep for the callers and check them' },
]

const UNITS_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  properties: {
    range: { type: 'string' },
    units: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        properties: {
          path: { type: 'string' },
          summary: { type: 'string' },
        },
        required: ['path', 'summary'],
      },
    },
  },
  required: ['range', 'units'],
}

const FINDINGS_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  properties: {
    tried: { type: 'string' },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        properties: {
          file: { type: 'string' },
          line: { type: 'integer' },
          summary: { type: 'string' },
          failure_scenario: { type: 'string' },
          severity: { type: 'string', enum: ['critical', 'high', 'medium', 'low'] },
        },
        required: ['file', 'line', 'summary', 'failure_scenario', 'severity'],
      },
    },
  },
  required: ['tried', 'findings'],
}

const VERDICT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  properties: {
    refuted: { type: 'boolean' },
    reason: { type: 'string' },
  },
  required: ['refuted', 'reason'],
}

phase('Scope')
const scope = await agent(
  [
    'You are scoping a code review. Do not review anything yet.',
    RANGE
      ? 'Diff range: ' + RANGE
      : 'No range was given. Resolve one: if HEAD has uncommitted changes, use the working tree vs HEAD. Otherwise use the merge-base of HEAD and the default branch (check `git remote show origin` or fall back to main/master) through HEAD.',
    'Run git to list every changed file in that range, excluding lockfiles, generated output, and vendored directories.',
    'Return the resolved range string and one unit per changed file with a one-line summary of what changed in it.',
    'If the range is empty, return an empty units array.',
  ].join('\n'),
  { label: 'scope', phase: 'Scope', schema: UNITS_SCHEMA }
)

if (!scope || !scope.units.length) {
  log('No reviewable changes found.')
  return { range: scope ? scope.range : null, confirmed: [], note: 'nothing to review' }
}

log(scope.units.length + ' file(s) in ' + scope.range + ' — ' + LENSES.length + ' lenses each, ' + REFUTERS + ' refuters per finding')

const attackPrompt = (unit, lens) =>
  [
    'You are an adversarial reviewer. You did not write this code and have no stake in it being',
    'correct. Your only job is to find bugs and concrete reasons it does not work. You never edit.',
    'Adversarially review ONE file in a diff. Assume the code is wrong; your job is to find why.',
    '',
    'Diff range: ' + scope.range,
    'File: ' + unit.path,
    'Change summary: ' + unit.summary,
    '',
    'Start by running: git diff ' + scope.range + ' -- ' + unit.path,
    'Read surrounding code and callers as needed for context, but judge the code by what it does.',
    '',
    'Your lens for this pass is ' + lens.key + '. Concentrate on: ' + lens.focus,
    'Other reviewers cover the other lenses — do not spread yourself thin.',
    '',
    'Your 10-turn ceiling still applies — depth here comes from many agents, not long ones.',
    'You have one file and one lens, which is what that budget is sized for. Two exceptions to',
    'your standing instructions: report every finding you can justify (not just your top 3), and',
    'fill in `tried` below even when you found nothing.',
    '',
    'Rules: no style, no naming, no "consider adding", no hypothetical refactors.',
    'Every finding needs concrete inputs or state and the resulting wrong behavior.',
    'If the code needs a paragraph-long comment to justify a workaround, the code is wrong — that is a finding.',
    'Try to disprove each of your own candidates before reporting it; drop the ones that die.',
    '',
    'In `tried`, state what you actively attempted to break and why it held. Never return an empty `tried`.',
  ].join('\n')

const refutePrompt = (f, unit, i) =>
  [
    'You are refuting a code review finding. Default to refuted=true when uncertain.',
    'A finding survives only if you can confirm the failure actually occurs.',
    '',
    'Diff range: ' + scope.range,
    'File: ' + unit.path,
    'Claim (' + f.severity + ', line ' + f.line + '): ' + f.summary,
    'Claimed failure: ' + f.failure_scenario,
    '',
    i === 0
      ? 'Angle: read the actual code and the diff. Does the described state even reach this line?'
      : i === 1
        ? 'Angle: check the callers, types, and existing tests. Is the input the claim requires actually possible here?'
        : 'Angle: try to reproduce it. Write or run the smallest check you can. If you cannot make it fail, say so.',
    '',
    'Set refuted=true if the claim is wrong, already handled elsewhere, unreachable, a style opinion,',
    'or describes pre-existing behavior this diff did not change.',
    'Set refuted=false only if the failure is real and this diff causes it.',
    '',
    'Budget: you are one vote of ' + REFUTERS + ' on one claim, so keep it to a handful of tool calls and',
    'batch independent ones into a single turn. If your angle needs more than that to settle, vote',
    'refuted=true and say what you could not check — an unsettled claim is exactly what a refuter',
    'is meant to catch.',
  ].join('\n')

const perFile = await pipeline(
  scope.units,

  (unit) =>
    parallel(
      LENSES.map((lens) => () =>
        agent(attackPrompt(unit, lens), {
          label: 'attack:' + lens.key + ':' + unit.path,
          phase: 'Attack',
          schema: FINDINGS_SCHEMA,
          agentType: 'adversary',
        })
      )
    ),

  (reviews, unit) => {
    const found = (reviews || []).filter(Boolean).flatMap((r) => r.findings)
    const seen = new Set()
    const fresh = found.filter((f) => {
      const k = f.file + ':' + f.line + ':' + f.summary.slice(0, 40).toLowerCase()
      if (seen.has(k)) return false
      seen.add(k)
      return true
    })
    if (!fresh.length) return []
    return parallel(
      fresh.map((f) => () =>
        parallel(
          Array.from({ length: REFUTERS }, (_, i) => () =>
            agent(refutePrompt(f, unit, i), {
              label: 'refute:' + i + ':' + unit.path + ':' + f.line,
              phase: 'Verify',
              schema: VERDICT_SCHEMA,
            })
          )
        ).then((votes) => {
          const cast = votes.filter(Boolean)
          const survived = cast.filter((v) => !v.refuted).length
          if (survived < THRESHOLD) return null
          return {
            file: f.file,
            line: f.line,
            severity: f.severity,
            summary: f.summary,
            failure_scenario: f.failure_scenario,
            verdict: survived === cast.length ? 'CONFIRMED' : 'PLAUSIBLE',
            votes: survived + '/' + cast.length,
          }
        })
      )
    )
  }
)

phase('Report')
const RANK = { critical: 0, high: 1, medium: 2, low: 3 }
const confirmed = perFile
  .filter(Boolean)
  .flat()
  .filter(Boolean)
  .sort((a, b) => RANK[a.severity] - RANK[b.severity])

log(confirmed.length + ' finding(s) survived refutation')

return {
  range: scope.range,
  files_reviewed: scope.units.length,
  lenses: LENSES.map((l) => l.key),
  confirmed,
}
