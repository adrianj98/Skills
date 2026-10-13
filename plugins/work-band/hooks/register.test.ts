import type { On, RenderElement } from 'claude-code'
import { expect, mock, test } from 'claude-code/testing'

import {
  applyLine,
  parseAuthStatus,
  candidatePorts,
  parseTopics,
  topicText,
  TOPIC_PROMPT,
  TOPIC_TOOL,
  CHROME_FOCUS_TAB,
  parsePort,
  rerunAll,
  rerunOne,
  runOf,
  parseShortstat,
  countChecks,
  finishTasks,
  formatDuration,
  keepLines,
  mergePlan,
  mergePrompt,
  fitWidth,
  firstRowWidth,
  parseDry,
  abbreviateStatus,
  parseJiraStatus,
  parseJiraTitle,
  pickJiraTool,
  parseTransitions,
  transitionPage,
  MORE,
  taskOfLine,
  toChecks,
  withoutPrefix,
} from './register'

type Engine = Parameters<Extract<Parameters<typeof test>[1], (...a: never[]) => unknown>>[0]

// Starts a session whose git remote is `origin`; gh finds no PR, Jira no key.
// `turbo run serve --dry=json` answers DRY, trimmed to the fields read.
const DRY = JSON.stringify({
  tasks: [
    { taskId: '//#serve', dependencies: ['//#kill-port'], resolvedTaskDefinition: { persistent: true } },
    { taskId: '//#kill-port', dependencies: [], resolvedTaskDefinition: { persistent: false } },
    { taskId: '//#build:watch', dependencies: ['//#kill-port'], resolvedTaskDefinition: { persistent: true } },
  ],
})

// Every argv the mod ran, so a test can see a press open a URL.
const ran: (readonly string[])[] = []
const opened = (url: string) => ran.some(a => a[0] === 'open' && a[1] === url)

const registered: string[] = []
const startIn = async ($: Engine, on: On, origin: string, prJson: string | (() => string) = '', clock = mock.clock(on), ownJira = false, store = new Map<string, unknown>(),
  git?: (argv: readonly string[]) => string | undefined,
) => {
  const prNow = () => (typeof prJson === 'function' ? prJson() : prJson)
  void clock
  on('process.run', (_$, e) => {
    ran.push(e.argv)
    const out = git?.(e.argv)
    if (out !== undefined) {
      return { value: { exitCode: 0, stdout: out, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
    }
    return {
    value: {
      exitCode:
        (e.argv[0] === 'git' && e.argv.includes('remote')) || e.argv.includes('--dry=json') || (e.argv[0] === 'gh' && prNow())
          ? 0
          : 1,
      stdout: e.argv.includes('remote')
        ? `${origin}\n`
        : e.argv.includes('--dry=json')
          ? DRY
          : e.argv[0] === 'gh'
            ? prNow()
            : '',
      stderr: '',
      isStdoutTruncated: false,
      isStderrTruncated: false,
    },
    }
  })
  on('ui.log', () => ({ value: undefined }) as never)
  on('store.get', (_$, e) => ({ value: store.get(e.key) }) as never)
  on('store.set', (_$, e) => {
    store.set(e.key, e.value)
    return { value: undefined } as never
  })
  // Jira's tool is neither listed nor allowed here unless a test answers
  // tool.list and tool.check itself.
  if (!ownJira) on('tool.list', () => ({ value: [] }) as never)
  if (!ownJira) on('tool.check', () => ({ decision: 'ask' }) as never)
  on('session.start', (_$, e) => ({ cwd: e.cwd }))
  on('command.register', (_$, e) => ({ value: { command: e.name } }))
  on('tool.register', (_$, e) => {
    registered.push(e.name)
    return { value: { tool: `mcp__work-band__${e.name}` } } as never
  })
  on('ui.render', () => h('Text', {}, 'engine default') as RenderElement)
  await $.session.start({ cwd: '/repo', surface: null, isInteractive: true })
}

const mountBand = ($: Engine, surface: 'terminal' | 'desktop', bodyColumns = 120) =>
  $.ui.mount({
    plugin: 'work-band',
    surface,
    component: 'AbovePrompt',
    props: { hasSurvey: false, isWorking: false, maxRows: 10, bodyColumns, scroll: { offset: 0, bodyRows: 10 }, view: {} },
  })

test('counts PR checks: skipped is neither pass nor fail, in-progress is pending', () => {
  expect(
    countChecks([
      { status: 'COMPLETED', conclusion: 'SUCCESS' },
      { status: 'COMPLETED', conclusion: 'FAILURE' },
      { status: 'COMPLETED', conclusion: 'SKIPPED' },
      { status: 'IN_PROGRESS', conclusion: null },
      { state: 'SUCCESS' },
    ]),
  ).toEqual({ passed: 2, failed: 1, pending: 1 })
})

// Lines as turbo 2.11.7 printed them for a probe repo (NO_COLOR).
const RUN = [
  '//:kill-port: cache bypass, force executing c733b315038b8cd6',
  '//:kill-port: ',
  '//:build:watch: cache bypass, force executing e5b82bf31e981f74',
  '//:build:watch: > npm run build -- --watch',
  '//:serve: cache bypass, force executing 0bacc14bfcda08d6',
  '//:serve: listening on 1776',
]

test('the plan lists turbo tasks dependencies first', () => {
  expect(parseDry(DRY).map(t => [t.name, t.state, t.persistent, t.deps])).toEqual([
    ['kill-port', 'pending', false, []],
    ['build:watch', 'pending', true, ['kill-port']],
    ['serve', 'pending', true, ['kill-port']],
  ])
})

test('a started task runs; its finished dependency is done', () => {
  const tasks = RUN.reduce(applyLine, parseDry(DRY))
  expect(tasks.map(t => [t.name, t.state])).toEqual([
    ['kill-port', 'done'],
    ['build:watch', 'running'],
    ['serve', 'running'],
  ])
})

test('an ERROR line fails the task with its exit code, colour codes or not', () => {
  const tasks = applyLine(
    RUN.reduce(applyLine, parseDry(DRY)),
    '\u001b[31m//#serve:  ERROR  command (/repo/) /bin/npm run serve:node exited (1)\u001b[0m',
  )
  expect(tasks.find(t => t.name === 'serve')).toMatchObject({ state: 'failed', code: 1 })
})

test('a run that ends stops what was running; a clean exit finishes one-shot tasks', () => {
  const started = applyLine(parseDry(DRY), RUN[0]!)
  expect(finishTasks(started, 0).map(t => t.state)).toEqual(['done', 'stopped', 'stopped'])
  const all = RUN.reduce(applyLine, parseDry(DRY))
  expect(finishTasks(all, null).map(t => t.state)).toEqual(['done', 'stopped', 'stopped'])
})

test('without a plan, tasks are learnt from the stream; the plan then orders them', () => {
  const seen = [RUN[4]!, RUN[2]!].reduce(applyLine, [] as ReturnType<typeof parseDry>)
  expect(seen.map(t => t.name)).toEqual(['serve', 'build:watch'])
  expect(mergePlan(parseDry(DRY), seen).map(t => [t.name, t.state])).toEqual([
    ['kill-port', 'pending'],
    ['build:watch', 'running'],
    ['serve', 'running'],
  ])
})

for (const surface of ['terminal', 'desktop'] as const) {
  test(`${surface}: the button starts t, then shows how it ended`, async ($, on) => {
    const spawned: string[][] = []
    const envs: (Record<string, string> | undefined)[] = []
    on('process.spawn', async function* (_$, e) {
      spawned.push([...e.argv])
      envs.push(e.env as Record<string, string> | undefined)
      yield { stream: 'stdout' as const, text: RUN.slice(0, 3).join('\n') + '\n//:ser' }
      yield { stream: 'stdout' as const, text: RUN.slice(4).join('\n').slice('//:ser'.length) + '\n' }
      return { value: { code: 0, signal: null } }
    })

    await startIn($, on, 'git@github.com:alert-d/alertd-core.git')
    const ui = await mountBand($, surface)
    expect((await ui.find({ key: 'serve' }))?.text).toBe('server')

    await ui.press({ key: 'serve' })

    expect(spawned).toEqual([['npx', 'turbo', 'run', 'serve', '--ui=stream']])
    expect(envs[0]).toMatchObject({ WEB_PORT: '1776', ORCHESTRATOR_SINGLETON_GATE: 'false' })
    expect(await ui.find({ type: 'Text', text: /exited 0$/ })).toBeDefined()
    // A line split across two chunks still counts; the run ended, so the
    // persistent tasks read stopped and the one-shot one done.
    expect((await ui.find({ type: 'Text', text: /kill-port/ }))?.text).toContain('✓ kill-port')
    expect((await ui.find({ type: 'Text', text: /build:watch/ }))?.text).toContain('■ build:watch')
    expect((await ui.find({ type: 'Text', text: /■ serve/ }))).toBeDefined()
  })
}

for (const surface of ['terminal', 'desktop'] as const) {
  test(`${surface}: outside alertd-core there is no t button`, async ($, on) => {
    await startIn($, on, 'git@github.com:someone/else.git')
    const ui = await mountBand($, surface)
    expect(await ui.find({ key: 'serve' })).toBe(undefined)
    expect(await ui.find({ type: 'Text', text: 'no PR' })).toBeDefined()
  })
}

for (const surface of ['terminal', 'desktop'] as const) {
  test(`${surface}: /wb hides the band, and again shows it`, async ($, on) => {
    await startIn($, on, 'git@github.com:alert-d/alertd-core.git')
    const ui = await mountBand($, surface)
    expect(await ui.find({ type: 'Text', text: 'no PR' })).toBeDefined()

    expect((await $.command.run({ command: 'wb', args: '' } as never)).text).toBe('Work band hidden. /wb shows it again.')
    expect(await ui.find({ type: 'Text', text: 'no PR' })).toBe(undefined)

    expect((await $.command.run({ command: 'wb', args: '' } as never)).text).toBe('Work band shown.')
    expect(await ui.find({ type: 'Text', text: 'no PR' })).toBeDefined()
  })
}

for (const surface of ['terminal', 'desktop'] as const) {
  test(`${surface}: while the server runs, ^ asks, and Kill stops it`, async ($, on) => {
    on('process.spawn', async function* (_$, _e, next) {
      yield { stream: 'stdout' as const, text: 'serve: listening on 1776\n' }
      await new Promise<void>(resolve => next.signal.addEventListener('abort', () => resolve()))
      return { value: { code: null, signal: 'SIGTERM' } }
    })
    const asked: string[] = []
    on('tool.call', { tool: 'AskUserQuestion' }, (_$, e) => {
      const q = e.questions[0]!
      asked.push(...q.options.map(o => o.label))
      return { result: { questions: e.questions, answers: { [q.question]: 'Kill' } } } as never
    })

    await startIn($, on, 'git@github.com:alert-d/alertd-core.git')
    const ui = await mountBand($, surface)
    await ui.press({ key: 'serve' })
    expect((await ui.find({ type: 'Text', text: /^server$/ }))?.props.color).toBe('success')

    await ui.press({ key: 'menu' })
    expect(asked).toEqual(['Restart', 'Kill', 'Change port', 'Cancel'])
    expect((await ui.find({ type: 'Text', text: /^server$/ }))?.props.color).toBe(undefined)
  })
}

for (const surface of ['terminal', 'desktop'] as const) {
  test(`${surface}: clicking server restarts it without asking`, async ($, on) => {
    let starts = 0
    on('process.spawn', async function* (_$, _e, next) {
      starts += 1
      yield { stream: 'stdout' as const, text: `//:serve: cache bypass, force executing ${starts}\n` }
      await new Promise<void>(resolve => next.signal.addEventListener('abort', () => resolve()))
      return { value: { code: null, signal: 'SIGTERM' } }
    })
    on('tool.call', { tool: 'AskUserQuestion' }, () => {
      throw new Error('server must not ask')
    })
    await startIn($, on, 'git@github.com:alert-d/alertd-core.git')
    const ui = await mountBand($, surface)

    await ui.press({ key: 'serve' })
    await ui.press({ key: 'serve' })
    expect(starts).toBe(2)
    expect((await ui.find({ type: 'Text', text: /^server$/ }))?.props.color).toBe('success')
    expect((await ui.find({ type: 'Text', text: /^● serve$/ }))?.props.color).toBe('success')
    expect((await ui.find({ type: 'Text', text: /kill-port/ }))?.text).toContain('✓ kill-port')
  })
}

for (const surface of ['terminal', 'desktop'] as const) {
  test(`${surface}: ^ on a stopped server offers Start`, async ($, on) => {
    let starts = 0
    on('process.spawn', async function* () {
      starts += 1
      yield { stream: 'stdout' as const, text: 'serve: up\n' }
      return { value: { code: 0, signal: null } }
    })
    const asked: string[] = []
    on('tool.call', { tool: 'AskUserQuestion' }, (_$, e) => {
      const q = e.questions[0]!
      asked.push(...q.options.map(o => o.label))
      return { result: { questions: e.questions, answers: { [q.question]: 'Start' } } } as never
    })
    await startIn($, on, 'git@github.com:alert-d/alertd-core.git')
    const ui = await mountBand($, surface)

    await ui.press({ key: 'menu' })
    expect(asked).toEqual(['Start', 'Change port', 'Cancel'])
    expect(starts).toBe(1)
  })
}

for (const surface of ['terminal', 'desktop'] as const) {
  test(`${surface}: the band draws a real PR, its Jira title and the server control`, async ($, on) => {
    on('tool.list', () => ({ value: [{ name: 'mcp__claude_ai_Atlassian_Rovo__getJiraIssue', description: '', mcp: true }] }) as never)
    on('tool.check', () => ({ decision: 'allow' }) as never)
    // No matcher: the tool-name union is laid from this machine's connectors.
    on('tool.call', (_$, e, next) =>
      e.tool === 'mcp__claude_ai_Atlassian_Rovo__getJiraIssue'
        ? ({ result: {}, text: '{"key":"AL-4169","fields":{"summary":"MATEOAS: route tables, apiPage helper","status":{"name":"To Do"}}}' } as never)
        : next(e),
    )
    await startIn(
      $,
      on,
      'git@github.com:alert-d/alertd-core.git',
      JSON.stringify({
        number: 2902,
        state: 'OPEN',
        isDraft: false,
        title: 'feat(mateoas): AL-4169 route tables',
        statusCheckRollup: [{ status: 'COMPLETED', conclusion: 'SUCCESS' }, { status: 'COMPLETED', conclusion: 'SKIPPED' }],
      }),
      mock.clock(on),
      true,
    )
    const ui = await mountBand($, surface)
    const row = (await ui.findAll({ type: 'Box' }))[1]!.text
    expect(row).toContain('PR #2902 open')
    expect(row).toContain('AL-4169 TODO MATEOAS: route tables, apiPage helper')
    expect(await ui.find({ type: 'Link' })).toBeUndefined()
    await ui.press({ key: 'jira' })
    expect(opened('https://alertd.atlassian.net/browse/AL-4169')).toBe(true)
    expect(row).toContain('[ server :1776 ^ ]')
  })
}

test('the title is the summary field, JSON escapes undone', () => {
  expect(parseJiraTitle('{"fields":{"summary":"Price the models \\u2014 \\"unpriced\\" ones","status":{"name":"To Do"}}}')).toBe(
    'Price the models \u2014 "unpriced" ones',
  )
  expect(parseJiraTitle('{"fields":{"status":{"name":"To Do"}}}')).toBe(undefined)
})

test('the status is the status field\'s name, as Jira nests it', () => {
  expect(
    parseJiraStatus(
      '{"fields":{"summary":"x","status":{"self":"https://x/status/3","description":"","iconUrl":"","name":"In Progress","id":"3","statusCategory":{"id":4,"name":"In Progress"}}}}',
    ),
  ).toBe('In Progress')
  expect(parseJiraStatus('{"fields":{"status":{"name":"S\\u00e9lection"}}}')).toBe('Sélection')
  expect(parseJiraStatus('{"fields":{"summary":"no status here"}}')).toBe(undefined)
})

test('a status abbreviates to a short tag', () => {
  expect(abbreviateStatus('To Do')).toBe('TODO')
  expect(abbreviateStatus('In Progress')).toBe('PROG')
  expect(abbreviateStatus('in review')).toBe('REV')
  expect(abbreviateStatus('Done')).toBe('DONE')
  expect(abbreviateStatus('Backlog')).toBe('BKLG')
  // Unknown: initials when several words, else the first four letters.
  expect(abbreviateStatus('Waiting for Customer')).toBe('WFC')
  expect(abbreviateStatus('Triage')).toBe('TRIA')
  expect(abbreviateStatus('  ')).toBe('')
})

test('the first row is measured as drawn; a title is cut to a width with an ellipsis', () => {
  const pr = { number: 2902, state: 'open', isDraft: false, passed: 1, failed: 0, pending: 0 } as never
  expect(firstRowWidth({ pr, diff: null, jira: { key: 'AL-1', title: 'Short' }, serve: '   [ server :1776 ^ ]', plan: 'Max' })).toBe(
    'PR #2902 open · diff · ✓1 ✗0 …0'.length + 3 + 'AL-1 Short'.length + '   [ server :1776 ^ ]'.length + '   Max'.length,
  )
  expect(firstRowWidth({ pr, diff: null, jira: { key: 'AL-1', title: 'Short', status: 'PROG' }, serve: '', plan: undefined })).toBe(
    firstRowWidth({ pr, diff: null, jira: { key: 'AL-1', title: 'Short' }, serve: '', plan: undefined }) + 'PROG '.length,
  )
  expect(firstRowWidth({ pr: null, diff: { added: 4, removed: 2, base: 'develop' }, jira: null, serve: '', plan: undefined })).toBe(
    'no PR · +4 −2 vs develop   no Jira key'.length,
  )
  expect(fitWidth('abcdef', 6)).toBe('abcdef')
  expect(fitWidth('abcdef', 4)).toBe('abc…')
  expect(fitWidth('abcdef', 1)).toBe('…')
})

for (const surface of ['terminal', 'desktop'] as const) {
  test(`${surface}: a title too wide for the row gets a row of its own, cut to the band`, async ($, on) => {
    const title = 'Bedrock Spend: price the models that show as unpriced, including Pegasus video seconds'
    on('tool.list', () => ({ value: [{ name: 'mcp__claude_ai_Atlassian_Rovo__getJiraIssue', description: '', mcp: true }] }) as never)
    on('tool.check', () => ({ decision: 'allow' }) as never)
    on('tool.call', (_$, e, next) =>
      e.tool === 'mcp__claude_ai_Atlassian_Rovo__getJiraIssue'
        ? ({ result: {}, text: JSON.stringify({ fields: { summary: title, status: { name: 'In Progress' } } }) } as never)
        : next(e),
    )
    await startIn($, on, 'git@github.com:alert-d/alertd-core.git', PR_WITH_KEY, mock.clock(on), true)
    // Wide enough: two rows, the status and title whole on the first.
    let ui = await mountBand($, surface, 200)
    let rows = await ui.findAll({ type: 'Box' })
    expect(rows[1]!.text).toContain(`AL-4169 PROG ${title}`)
    expect(rows.length).toBe(2)
    // Too narrow: the issue moves to its own row, cut to 60 cells, and the
    // first row keeps the PR and the server control.
    ui = await mountBand($, surface, 60)
    rows = await ui.findAll({ type: 'Box' })
    expect(rows.length).toBe(3)
    expect(rows[1]!.text).not.toContain('AL-4169')
    expect(rows[1]!.text).toContain('PR #1 open')
    expect(rows[1]!.text).toContain('[ server :1776 ^ ]')
    expect(rows[2]!.text).toBe(`AL-4169 PROG ${title.slice(0, 60 - 'AL-4169 PROG '.length - 1)}…`)
    expect(rows[2]!.text.length).toBe(60)
    await ui.press({ key: 'jira' })
    expect(opened('https://alertd.atlassian.net/browse/AL-4169')).toBe(true)
  })
}

test('the Jira tool is whichever connected server serves getJiraIssue', () => {
  expect(pickJiraTool(['Bash', 'mcp__claude_ai_Atlassian_Rovo__getJiraIssue', 'mcp__claude_ai_Atlassian_Rovo__search'])).toBe(
    'mcp__claude_ai_Atlassian_Rovo__getJiraIssue',
  )
  expect(pickJiraTool(['mcp__atlassian__getJiraIssue'])).toBe('mcp__atlassian__getJiraIssue')
  expect(pickJiraTool(['mcp__claude_ai_Atlassian__getJiraIssueRemoteIssueLinks', 'Read'])).toBe(undefined)
})

const PR_WITH_KEY = JSON.stringify({ number: 1, state: 'OPEN', isDraft: false, title: 'AL-4169 x', statusCheckRollup: [] })

test('the band reads the title from a local atlassian server too', async ($, on) => {
  on('tool.list', () => ({ value: [{ name: 'mcp__atlassian__getJiraIssue', description: '', mcp: true }] }) as never)
  on('tool.check', () => ({ decision: 'allow' }) as never)
  on('tool.call', (_$, e, next) =>
    (e.tool as string) === 'mcp__atlassian__getJiraIssue' ? ({ result: {}, text: '{"fields":{"summary":"Say \\"hi\\" \\u00e9"}}' } as never) : next(e),
  )
  await startIn($, on, 'git@github.com:alert-d/alertd-core.git', PR_WITH_KEY, mock.clock(on), true)
  const ui = await mountBand($, 'terminal')
  expect((await ui.findAll({ type: 'Box' }))[1]!.text).toContain('AL-4169 Say "hi" é')
})

test('the band names the tool to allow, and says when no Jira server is connected', async ($, on) => {
  let listed: string[] = []
  on('tool.list', () => ({ value: listed.map(name => ({ name, description: '', mcp: true })) }) as never)
  on('tool.check', () => ({ decision: 'ask' }) as never)
  const clock = mock.clock(on)
  await startIn($, on, 'git@github.com:alert-d/alertd-core.git', PR_WITH_KEY, clock, true)
  let ui = await mountBand($, 'terminal')
  expect((await ui.findAll({ type: 'Box' }))[1]!.text).toContain('AL-4169 no Jira MCP connected')
  listed = ['mcp__claude_ai_Atlassian_Rovo__getJiraIssue']
  await clock.advance(120_000)
  ui = await mountBand($, 'terminal')
  expect((await ui.findAll({ type: 'Box' }))[1]!.text).toContain('AL-4169 allow mcp__claude_ai_Atlassian_Rovo__getJiraIssue to show the title')
})

test('the transitions are read from getTransitionsForJiraIssue, unavailable ones left out', () => {
  const text = JSON.stringify({
    transitions: [
      { id: '11', name: 'To Do', to: { name: 'To Do' } },
      { id: '21', name: 'Start', to: { name: 'In Progress' } },
      { id: '9', name: 'Gone', isAvailable: false, to: { name: 'Gone' } },
    ],
  })
  expect(parseTransitions(text)).toEqual([
    { id: '11', name: 'To Do', to: 'To Do' },
    { id: '21', name: 'Start', to: 'In Progress' },
  ])
  expect(parseTransitions('not json')).toEqual([])
})

test('a long transition list is paged three at a time with More…', () => {
  const names = ['a', 'b', 'c', 'd', 'e', 'f', 'g']
  expect(transitionPage(names, 0)).toEqual(['a', 'b', 'c', MORE])
  expect(transitionPage(names, 1)).toEqual(['d', 'e', 'f', 'g'])
  expect(transitionPage(['a', 'b', 'c', 'd'], 0)).toEqual(['a', 'b', 'c', 'd'])
})

test('clicking the status lists the other statuses and moves the issue to the one picked', async ($, on) => {
  let status = 'To Do'
  const moved: unknown[] = []
  const asked: string[][] = []
  const answers = [MORE, 'QA']
  const R = 'mcp__claude_ai_Atlassian_Rovo__'
  on('ui.toast', () => ({ value: undefined }) as never)
  on('tool.list', () => ({ value: ['getJiraIssue', 'getTransitionsForJiraIssue', 'transitionJiraIssue'].map(n => ({ name: R + n, description: '', mcp: true })) }) as never)
  on('tool.check', () => ({ decision: 'allow' }) as never)
  on('tool.call', { tool: 'AskUserQuestion' }, (_$, e) => {
    const q = e.questions[0]!
    asked.push(q.options.map(o => o.label))
    return { result: { questions: e.questions, answers: { [q.question]: answers.shift()! } } } as never
  })
  on('tool.call', (_$, e, next) => {
    const t = e.tool as string
    if (t === R + 'getJiraIssue') return { result: {}, text: JSON.stringify({ fields: { summary: 'Routes', status: { name: status } } }) } as never
    if (t === R + 'getTransitionsForJiraIssue')
      return {
        result: {},
        text: JSON.stringify({
          transitions: ["Won't Do", 'To Do', 'In Progress', 'Done', 'In Review', 'QA', 'RELEASE QA'].map((name, i) => ({ id: String(i), name, to: { name } })),
        }),
      } as never
    if (t === R + 'transitionJiraIssue') {
      moved.push((e as unknown as { transition: unknown }).transition)
      status = 'QA'
      return { result: {}, text: '' } as never
    }
    return next(e)
  })
  await startIn($, on, 'git@github.com:alert-d/alertd-core.git', PR_WITH_KEY, mock.clock(on), true)
  const ui = await mountBand($, 'terminal')
  expect((await ui.findAll({ type: 'Box' }))[1]!.text).toContain('AL-4169 TODO Routes')
  await ui.press({ key: 'jira-state' })
  // To Do, the current status, is not offered.
  expect(asked).toEqual([
    ["Won't Do", 'In Progress', 'Done', MORE],
    ['In Review', 'QA', 'RELEASE QA'],
  ])
  expect(moved).toEqual([{ id: '5' }])
  expect((await ui.findAll({ type: 'Box' }))[1]!.text).toContain('AL-4169 QA Routes')
})

test('a refused transitions call says why, rather than offering nothing', async ($, on) => {
  const toasts: string[] = []
  const R = 'mcp__claude_ai_Atlassian_Rovo__'
  on('ui.toast', (_$, e) => {
    toasts.push(e.text)
    return { value: undefined } as never
  })
  on('tool.list', () => ({ value: ['getJiraIssue', 'getTransitionsForJiraIssue', 'transitionJiraIssue'].map(n => ({ name: R + n, description: '', mcp: true })) }) as never)
  on('tool.check', () => ({ decision: 'allow' }) as never)
  on('tool.call', (_$, e, next) => {
    const t = e.tool as string
    if (t === R + 'getJiraIssue') return { result: {}, text: JSON.stringify({ fields: { summary: 'Routes', status: { name: 'To Do' } } }) } as never
    if (t === R + 'getTransitionsForJiraIssue') return { deny: 'denied by auto mode' } as never
    return next(e)
  })
  await startIn($, on, 'git@github.com:alert-d/alertd-core.git', PR_WITH_KEY, mock.clock(on), true)
  const ui = await mountBand($, 'terminal')
  await ui.press({ key: 'jira-state' })
  expect(toasts).toEqual(["Could not list AL-4169's statuses: denied by auto mode"])
})

test('a line names the task that printed it', () => {
  expect(taskOfLine('//:build:watch: > npm run build -- --watch')).toBe('build:watch')
  expect(taskOfLine('\u001b[2m//:serve:\u001b[0m listening on 1776')).toBe('serve')
  expect(taskOfLine(' Tasks:    2 successful, 3 total')).toBe(undefined)
})

for (const surface of ['terminal', 'desktop'] as const) {
  test(`${surface}: a running task's dot lights up while it prints, then dims`, async ($, on) => {
    const clock = mock.clock(on)
    let print: (text: string) => void = () => {}
    on('process.spawn', async function* (_$, _e, next) {
      const queue: string[] = []
      let wake: () => void = () => {}
      print = text => {
        queue.push(text)
        wake()
      }
      next.signal.addEventListener('abort', () => wake())
      while (!next.signal.aborted) {
        if (!queue.length) await new Promise<void>(resolve => (wake = resolve))
        while (queue.length) yield { stream: 'stdout' as const, text: queue.shift()! }
      }
      return { value: { code: null, signal: 'SIGTERM' } }
    })
    await startIn($, on, 'git@github.com:alert-d/alertd-core.git', '', clock)
    const ui = await mountBand($, surface)
    await ui.press({ key: 'serve' })

    const dot = async () => (await ui.find({ type: 'Text', text: /^● build:watch$/ }))?.props
    print(RUN.slice(0, 3).join('\n') + '\n')
    await clock.advance(1)
    expect(await dot()).toMatchObject({ bold: true, dimColor: false })

    await clock.advance(400)
    expect(await dot()).toMatchObject({ bold: false, dimColor: true })

    print('//:build:watch: rebuilt in 120ms\n')
    await clock.advance(1)
    expect(await dot()).toMatchObject({ bold: true, dimColor: false })
  })
}

test('logs keep the last lines, without the task prefix', () => {
  expect(keepLines(['a', 'b'], ['c', 'd'], 3)).toEqual(['b', 'c', 'd'])
  expect(withoutPrefix('//:build:watch: > npm run build -- --watch')).toBe('> npm run build -- --watch')
})

for (const surface of ['terminal', 'desktop'] as const) {
  test(`${surface}: clicking a task opens its logs, and again closes them`, async ($, on) => {
    on('process.spawn', async function* (_$, _e, next) {
      yield { stream: 'stdout' as const, text: RUN.join('\n') + '\n//:serve: GET /health 200\n' }
      await new Promise<void>(resolve => next.signal.addEventListener('abort', () => resolve()))
      return { value: { code: null, signal: 'SIGTERM' } }
    })
    const open = new Set<string>()
    const titles: string[] = []
    on('ui.open', (_$, e) => {
      open.add(e.id)
      titles.push(e.title ?? '')
      return { value: { isPlaced: true } } as never
    })
    on('ui.close', (_$, e) => {
      open.delete(e.id)
      return { value: undefined } as never
    })
    on('ui.panes', () => ({ value: [...open].map(id => ({ id, title: '' })) }) as never)
    await startIn($, on, 'git@github.com:alert-d/alertd-core.git')
    const band = await mountBand($, surface)
    await band.press({ key: 'serve' })

    await band.press({ key: 'task-serve' })
    expect(titles).toEqual(['serve logs'])
    const pane = await $.ui.mount({
      plugin: 'work-band',
      surface,
      component: 'Pane',
      requestId: 'server-logs',
      props: {
        title: 'serve logs',
        isFocused: false,
        bodyColumns: 100,
        placement: 'dock',
        scroll: { offset: 0, bodyRows: 2 },
      } as never,
    })
    const shown = (await pane.findAll({ type: 'Text' })).map(t => t.text)
    expect(shown).toEqual(['listening on 1776', 'GET /health 200'])

    await band.press({ key: 'task-serve' })
    expect(open.size).toBe(0)
  })
}

// Two entries of `gh pr view 2902 --json statusCheckRollup`, as gh returned them.
const ROLLUP = [
  {
    __typename: 'CheckRun',
    completedAt: '2026-10-09T02:49:41Z',
    conclusion: 'SUCCESS',
    detailsUrl: 'https://github.com/alert-d/alertd-core/actions/runs/37876304161/job/113645611425',
    name: 'claude-review',
    startedAt: '2026-10-09T02:48:29Z',
    status: 'COMPLETED',
    workflowName: 'Claude Code Review',
  },
  {
    __typename: 'CheckRun',
    completedAt: '2026-10-09T04:34:54Z',
    conclusion: 'FAILURE',
    detailsUrl: 'https://github.com/alert-d/alertd-core/actions/runs/37876304171/job/113664504427',
    name: 'integration (server)',
    startedAt: '2026-10-09T04:06:14Z',
    status: 'COMPLETED',
    workflowName: 'Integration Test',
  },
  { __typename: 'CheckRun', name: 'vitest', status: 'IN_PROGRESS', conclusion: '', startedAt: '2026-10-09T05:00:00Z', completedAt: '0001-01-01T00:00:00Z', workflowName: 'CI' },
  { __typename: 'StatusContext', context: 'deploy/preview', state: 'SUCCESS', targetUrl: 'https://example.test/preview' },
]

test('checks list failures first, then running, then passed', () => {
  expect(toChecks(ROLLUP).map(c => [c.name, c.state, c.completedAt ?? null])).toEqual([
    ['integration (server)', 'fail', '2026-10-09T04:34:54Z'],
    ['vitest', 'pending', null],
    ['claude-review', 'pass', '2026-10-09T02:49:41Z'],
    ['deploy/preview', 'pass', null],
  ])
  expect(countChecks(ROLLUP)).toEqual({ passed: 2, failed: 1, pending: 1 })
})

test('durations read short', () => {
  expect(formatDuration(72_000)).toBe('1m 12s')
  expect(formatDuration(28 * 60_000 + 40_000)).toBe('28m 40s')
  expect(formatDuration(3_720_000)).toBe('1h 02m')
  expect(formatDuration(9_000)).toBe('9s')
})

const prJson = (state: string) =>
  JSON.stringify({ number: 2902, state, isDraft: false, title: 'feat(mateoas): AL-4169 route tables', statusCheckRollup: ROLLUP })

const paneHooks = (on: On) => {
  const open = new Set<string>()
  on('ui.open', (_$, e) => {
    open.add(e.id)
    return { value: { isPlaced: true } } as never
  })
  on('ui.close', (_$, e) => {
    open.delete(e.id)
    return { value: undefined } as never
  })
  on('ui.panes', () => ({ value: [...open].map(id => ({ id, title: '' })) }) as never)
  return open
}

for (const surface of ['terminal', 'desktop'] as const) {
  test(`${surface}: clicking the CI counts opens each check's result`, async ($, on) => {
    const open = paneHooks(on)
    await startIn($, on, 'git@github.com:alert-d/alertd-core.git', prJson('OPEN'))
    const band = await mountBand($, surface)
    await band.press({ key: 'checks' })
    expect([...open]).toEqual(['pr-checks'])

    const pane = await $.ui.mount({
      plugin: 'work-band',
      surface,
      component: 'Pane',
      requestId: 'pr-checks',
      props: { title: 'PR #2902 checks', isFocused: false, bodyColumns: 100, placement: 'dock', scroll: { offset: 0, bodyRows: 10 } } as never,
    })
    const boxes = (await pane.findAll({ type: 'Box' })).map(b => b.text)
    expect(boxes[1]).toBe('Re-run failed and skipped (1)')
    const rows = boxes.slice(2)
    expect(rows[0]).toBe('✗ integration (server) · Integration Test · 28m 40s details rerun')
    expect(rows[2]).toBe('✓ claude-review · Claude Code Review · 1m 12s details')
    expect(rows[3]).toBe('✓ deploy/preview details')
    await pane.press({ key: 'link-Integration Test/integration (server)' })
    expect(opened('https://github.com/alert-d/alertd-core/actions/runs/37876304171/job/113664504427')).toBe(true)

    await band.press({ key: 'checks' })
    expect(open.size).toBe(0)
  })
}

test('the merge prompt names the PR and its Jira issue', () => {
  expect(mergePrompt(2902, 'feat: AL-4169 x', 'AL-4169')).toBe(
    'PR #2902 ("feat: AL-4169 x") has just been merged; the work-band mod saw it change from open to merged. Its Jira issue is AL-4169. Update AL-4169 for the merge, following this project\'s Jira rules.',
  )
})

test('open → merged tells the model once; a PR merged before the session does not', async ($, on) => {
  const clock = mock.clock(on)
  let state = 'OPEN'
  const prompts: string[] = []
  on('prompt.submit', (_$, e) => {
    prompts.push(e.text)
    return { text: e.text } as never
  })
  on('ui.toast', () => ({ value: undefined }) as never)
  await startIn($, on, 'git@github.com:alert-d/alertd-core.git', () => prJson(state), clock)
  await clock.advance(1)
  expect(prompts).toEqual([])

  state = 'MERGED'
  await clock.advance(120_000)
  await clock.advance(120_000)
  expect(prompts).toEqual([mergePrompt(2902, 'feat(mateoas): AL-4169 route tables', 'AL-4169')])
})

test('a PR already merged when the session starts tells nothing', async ($, on) => {
  const clock = mock.clock(on)
  const prompts: string[] = []
  on('prompt.submit', (_$, e) => {
    prompts.push(e.text)
    return { text: e.text } as never
  })
  await startIn($, on, 'git@github.com:alert-d/alertd-core.git', prJson('MERGED'), clock)
  await clock.advance(240_000)
  expect(prompts).toEqual([])
})

test('a port is a whole number from 1 to 65535', () => {
  expect(['1791', ' 8080 ', '0', '65536', '17.5', 'abc', ''].map(parsePort)).toEqual([
    1791,
    8080,
    undefined,
    undefined,
    undefined,
    undefined,
    undefined,
  ])
})

for (const surface of ['terminal', 'desktop'] as const) {
  test(`${surface}: Change port restarts the running server on the new WEB_PORT and remembers it`, async ($, on) => {
    const ports: (string | undefined)[] = []
    on('process.spawn', async function* (_$, e, next) {
      ports.push(e.env?.WEB_PORT)
      yield { stream: 'stdout' as const, text: '//:serve: cache bypass, force executing 1\n' }
      await new Promise<void>(resolve => next.signal.addEventListener('abort', () => resolve()))
      return { value: { code: null, signal: 'SIGTERM' } }
    })
    const answers = ['Change port', '1791']
    on('tool.call', { tool: 'AskUserQuestion' }, (_$, e) => {
      const q = e.questions[0]!
      return { result: { questions: e.questions, answers: { [q.question]: answers.shift()! } } } as never
    })
    const store = new Map<string, unknown>()
    await startIn($, on, 'git@github.com:alert-d/alertd-core.git', '', mock.clock(on), false, store)
    const ui = await mountBand($, surface)
    expect(await ui.find({ type: 'Text', text: /:1776/ })).toBeDefined()

    await ui.press({ key: 'serve' })
    await ui.press({ key: 'menu' })

    expect(ports).toEqual(['1776', '1791'])
    expect(store.get('port')).toBe(1791)
    expect(await ui.find({ type: 'Text', text: /:1791/ })).toBeDefined()
  })
}

test('a remembered port is used from the start of the next session', async ($, on) => {
  const ports: (string | undefined)[] = []
  on('process.spawn', async function* (_$, e) {
    ports.push(e.env?.WEB_PORT)
    return { value: { code: 0, signal: null } }
  })
  await startIn($, on, 'git@github.com:alert-d/alertd-core.git', '', mock.clock(on), false, new Map([['port', 1792]]))
  const ui = await mountBand($, 'terminal')
  await ui.press({ key: 'serve' })
  expect(ports).toEqual(['1792'])
})

// A repo of five files: two changed in the PR, one of them and one new
// file uncommitted.
const REPO = (argv: readonly string[]) => {
  const cmd = argv.join(' ')
  if (cmd === 'git rev-parse --show-toplevel') return '/repo\n'
  if (cmd.endsWith(' ls-files')) return ['README.md', 'src/a.ts', 'src/b.ts', 'src/deep/c.ts', 'docs/d.md'].join('\n') + '\n'
  if (cmd.includes(' status --porcelain')) return ' M src/b.ts\n?? src/new.ts\n'
  if (cmd.includes(' diff --name-status origin/develop...HEAD')) return 'M\tsrc/a.ts\nM\tsrc/b.ts\n'
  return undefined
}

const mountFiles = ($: Engine, surface: 'terminal' | 'desktop') =>
  $.ui.mount({
    plugin: 'work-band',
    surface,
    component: 'Pane',
    requestId: 'files',
    props: { title: 'Files', isFocused: false, bodyColumns: 100, placement: 'dock', scroll: { offset: 0, bodyRows: 30 } } as never,
  })

for (const surface of ['terminal', 'desktop'] as const) {
  test(`${surface}: with the filetree mod installed, Files runs /filetree instead of opening its own pane`, async ($, on) => {
    const open = paneHooks(on)
    const runs: string[] = []
    const toasts: string[] = []
    let answer = 'File tree on ~/alertd-core (follows the cwd).'
    on('command.list', () => ({ value: [{ name: 'filetree', description: 'Show the file tree', source: 'plugin', plugin: 'filetree' }] }) as never)
    on('command.run', { command: 'filetree' }, (_$, e) => {
      runs.push(`${e.command} ${e.args}`.trim())
      return { text: answer }
    })
    on('ui.toast', (_$, e) => {
      toasts.push(e.text)
      return { value: undefined } as never
    })
    await startIn($, on, 'git@github.com:alert-d/alertd-core.git', '', mock.clock(on), false, new Map(), REPO)
    const band = await mountBand($, surface)
    await band.press({ key: 'files' })
    expect(runs).toEqual(['filetree'])
    expect([...open]).toEqual([])
    expect(toasts).toEqual([])
    // filetree's refusal reaches the person as a toast.
    answer = 'filetree shows in the sidebar, which needs a terminal at least 110 columns wide. Widen it, then run /filetree.'
    await band.press({ key: 'files' })
    expect(toasts).toEqual([answer])
  })
}

test('without the filetree mod, Files opens the band\'s own pane', async ($, on) => {
  const open = paneHooks(on)
  on('command.list', () => ({ value: [{ name: 'wb', description: '', source: 'plugin', plugin: 'work-band' }] }) as never)
  await startIn($, on, 'git@github.com:alert-d/alertd-core.git', '', mock.clock(on), false, new Map(), REPO)
  const band = await mountBand($, 'terminal')
  await band.press({ key: 'files' })
  expect([...open]).toEqual(['files'])
})

const fileRows = async (pane: { findAll: (q: { type: string }) => Promise<{ text: string; key: string | undefined }[]> }) =>
  (await pane.findAll({ type: 'Text' }))
    .filter(t => /^ *(?:[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏] |  )\S/.test(t.text) || /^ *[▸▾] /.test(t.text))
    .map(t => t.text.trimEnd())

for (const surface of ['terminal', 'desktop'] as const) {
  test(`${surface}: clicking the PR opens the files, PR changes first, uncommitted in another colour`, async ($, on) => {
    const open = paneHooks(on)
    await startIn($, on, 'git@github.com:alert-d/alertd-core.git', '', mock.clock(on), false, new Map(), REPO)
    const band = await mountBand($, surface)
    await band.press({ key: 'files' })
    expect([...open]).toEqual(['files'])

    const pane = await mountFiles($, surface)
    expect((await pane.find({ key: 'mode-pr' }))?.text).toBe('PR 2')
    expect((await pane.find({ key: 'mode-uncommitted' }))?.text).toBe('Uncommitted 2')
    expect((await pane.find({ type: 'Text', text: /^a\.ts$/ }))?.props.color).toBe('suggestion')
    expect((await pane.find({ type: 'Text', text: /^b\.ts$/ }))?.props.color).toBe('warning')
    expect((await pane.find({ type: 'Text', text: /^src\/$/ }))?.props.color).toBe('warning')
    expect(await pane.find({ type: 'Text', text: /README/ })).toBe(undefined)

    await pane.press({ key: 'mode-all' })
    expect(await pane.find({ type: 'Text', text: /^README\.md$/ })).toBeDefined()
    expect(await pane.find({ type: 'Text', text: /^a\.ts$/ })).toBe(undefined) // src/ starts closed
    await pane.press({ key: 'dir:src' })
    expect(await pane.find({ type: 'Text', text: /^a\.ts$/ })).toBeDefined()
    expect(await pane.find({ type: 'Text', text: /^new\.ts$/ })).toBeDefined()

    await pane.press({ key: 'mode-uncommitted' })
    expect(await pane.find({ type: 'Text', text: /^a\.ts$/ })).toBe(undefined)
    expect(await pane.find({ type: 'Text', text: /^new\.ts$/ })).toBeDefined()
  })
}

test('the file being edited spins, its folders open, and stops after the edit', async ($, on) => {
  const clock = mock.clock(on)
  paneHooks(on)
  let finishEdit: () => void = () => {}
  on('tool.call', { tool: 'Edit' }, () => new Promise(resolve => (finishEdit = () => resolve({ result: {}, text: 'ok' } as never))))
  await startIn($, on, 'git@github.com:alert-d/alertd-core.git', '', clock, false, new Map(), REPO)
  const band = await mountBand($, 'terminal')
  await band.press({ key: 'files' })
  const pane = await mountFiles($, 'terminal')
  await pane.press({ key: 'mode-all' })

  const edit = $.tool.call({ tool: 'Edit', file_path: '/repo/src/deep/c.ts', old_string: 'a', new_string: 'b' } as never)
  await clock.advance(1)
  const spinning = await pane.find({ type: 'Text', text: /^[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏] $/ })
  expect(spinning).toBeDefined()
  expect(await pane.find({ type: 'Text', text: /^c\.ts$/ })).toBeDefined() // src/ and src/deep/ opened for it
  const first = spinning!.text
  await clock.advance(120)
  expect((await pane.find({ type: 'Text', text: /^[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏] $/ }))?.text).not.toBe(first)

  finishEdit()
  await edit
  await clock.advance(1600)
  expect(await pane.find({ type: 'Text', text: /^[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏] $/ })).toBe(undefined)
})

test('git diff --shortstat counts, either side left out when zero', () => {
  expect(parseShortstat(' 31 files changed, 2450 insertions(+), 271 deletions(-)\n')).toEqual({ added: 2450, removed: 271 })
  expect(parseShortstat(' 1 file changed, 1 insertion(+)\n')).toEqual({ added: 1, removed: 0 })
  expect(parseShortstat(' 2 files changed, 9 deletions(-)\n')).toEqual({ added: 0, removed: 9 })
  expect(parseShortstat('')).toEqual({ added: 0, removed: 0 })
})

const SHORTSTAT = (base: string) => (argv: readonly string[]) =>
  argv.join(' ') === `git diff --shortstat origin/${base}...HEAD`
    ? ' 31 files changed, 2450 insertions(+), 271 deletions(-)\n'
    : REPO(argv)

for (const surface of ['terminal', 'desktop'] as const) {
  test(`${surface}: PR # links to the PR; the diff against its base opens the files`, async ($, on) => {
    const open = paneHooks(on)
    const prBody = JSON.stringify({
      number: 2902,
      state: 'OPEN',
      isDraft: false,
      title: 'feat(mateoas): AL-4169 route tables',
      baseRefName: 'release/1.4',
      url: 'https://github.com/alert-d/alertd-core/pull/2902',
      statusCheckRollup: [],
    })
    await startIn($, on, 'git@github.com:alert-d/alertd-core.git', prBody, mock.clock(on), false, new Map(), SHORTSTAT('release/1.4'))
    const band = await mountBand($, surface)
    const row = (await band.findAll({ type: 'Box' }))[1]!.text
    expect(row).toContain('PR #2902 open · +2450 −271 · ✓0 ✗0 …0')
    await band.press({ key: 'pr' })
    expect(opened('https://github.com/alert-d/alertd-core/pull/2902')).toBe(true)

    await band.press({ key: 'files' })
    expect([...open]).toEqual(['files'])
  })

  test(`${surface}: with no PR the diff is against develop, and says so`, async ($, on) => {
    await startIn($, on, 'git@github.com:alert-d/alertd-core.git', '', mock.clock(on), false, new Map(), SHORTSTAT('develop'))
    const band = await mountBand($, surface)
    expect((await band.findAll({ type: 'Box' }))[1]!.text).toContain('no PR · +2450 −271 vs develop')
  })
}

test('a check link names its run and job', () => {
  expect(runOf('https://github.com/alert-d/alertd-core/actions/runs/37876304171/job/113664504427')).toEqual({
    run: '37876304171',
    job: '113664504427',
  })
  expect(runOf('https://example.test/preview')).toBe(undefined)
})

const check = (name: string, state: 'pass' | 'fail' | 'pending' | 'skipped', run: string, job: string) => ({
  name,
  state,
  url: `https://github.com/alert-d/alertd-core/actions/runs/${run}/job/${job}`,
})

test('one check: a failed job alone, a skipped one with its whole run, a passed one never', () => {
  expect(rerunOne(check('vitest', 'fail', '1', '11'))).toEqual(['gh', 'run', 'rerun', '1', '--job', '11'])
  expect(rerunOne(check('integration', 'skipped', '2', '21'))).toEqual(['gh', 'run', 'rerun', '2'])
  expect(rerunOne(check('prettier', 'pass', '3', '31'))).toBe(undefined)
  expect(rerunOne({ name: 'deploy/preview', state: 'fail', url: 'https://example.test/x' })).toBe(undefined)
})

test('all: one command per run; skipped wins over failed; running runs are left alone', () => {
  expect(
    rerunAll([
      check('vitest', 'fail', '1', '11'),
      check('prettier', 'fail', '1', '12'),
      check('integration (rest)', 'skipped', '2', '21'),
      check('integration (server)', 'fail', '2', '22'),
      check('playwright', 'fail', '3', '31'),
      check('playwright-2', 'pending', '3', '32'),
      check('security', 'pass', '4', '41'),
    ]),
  ).toEqual([
    ['gh', 'run', 'rerun', '1', '--failed'],
    ['gh', 'run', 'rerun', '2'],
  ])
})

for (const surface of ['terminal', 'desktop'] as const) {
  test(`${surface}: rerun on a failed check runs gh for that job, then says it was asked`, async ($, on) => {
    paneHooks(on)
    on('ui.toast', () => ({ value: undefined }) as never)
    const ran: string[] = []
    await startIn($, on, 'git@github.com:alert-d/alertd-core.git', prJson('OPEN'), mock.clock(on), false, new Map(), argv => {
      if (argv[0] === 'gh' && argv[1] === 'run') {
        ran.push(argv.join(' '))
        return ''
      }
      return undefined
    })
    const band = await mountBand($, surface)
    await band.press({ key: 'checks' })
    const pane = await $.ui.mount({
      plugin: 'work-band',
      surface,
      component: 'Pane',
      requestId: 'pr-checks',
      props: { title: 'PR #2902 checks', isFocused: false, bodyColumns: 100, placement: 'dock', scroll: { offset: 0, bodyRows: 10 } } as never,
    })
    await pane.press({ key: 'rerun:Integration Test/integration (server)' })
    expect(ran).toEqual(['gh run rerun 37876304171 --job 113664504427'])
    const row = (await pane.findAll({ type: 'Box' })).find(b => b.text.startsWith('✗ integration (server)'))
    expect(row?.text).toContain('re-run asked')
    expect(await pane.find({ key: 'rerun-all' })).toBe(undefined)
  })
}

for (const surface of ['terminal', 'desktop'] as const) {
  test(`${surface}: the port opens the server in Chrome's existing tab, else plain open`, async ($, on) => {
    const ran: string[][] = []
    let chromeWorks = true
    const store = new Map<string, unknown>([['port', 1791]])
    await startIn($, on, 'git@github.com:alert-d/alertd-core.git', '', mock.clock(on), false, store, argv => {
      if (argv[0] === 'osascript' || argv[0] === 'open') {
        ran.push([...argv])
        if (argv[0] === 'osascript' && !chromeWorks) throw new Error('Not authorised to send Apple events to Google Chrome')
        return 'reused'
      }
      return undefined
    })
    const band = await mountBand($, surface)
    expect((await band.find({ key: 'port' }))?.text).toBe(':1791')

    await band.press({ key: 'port' })
    expect(ran).toEqual([['osascript', '-e', CHROME_FOCUS_TAB, 'http://localhost:1791']])

    chromeWorks = false
    ran.length = 0
    await band.press({ key: 'port' })
    expect(ran.map(a => a[0])).toEqual(['osascript', 'open'])
    expect(ran[1]).toEqual(['open', 'http://localhost:1791'])
  })
}

test('topics: trimmed, blanks dropped, at most three; not a list is undefined', () => {
  expect(parseTopics({ topics: [' Jira status ', '', 'port picking'] })).toEqual(['Jira status', 'port picking'])
  expect(parseTopics({ topics: ['a', 'b', 'c', 'd'] })).toEqual(['a', 'b', 'c'])
  expect(parseTopics({ topics: 'a' })).toBeUndefined()
  expect(parseTopics({ topics: ['a', 2] })).toBeUndefined()
  expect(parseTopics({})).toBeUndefined()
  expect(topicText(['a', 'b'])).toBe('a · b')
})

test('the topic prompt section is added when set_topic is on offer, with the engine sections ahead of it', async ($, on) => {
  on('prompt.compose', () => ({ sections: [{ id: 'intro', text: 'hi', scope: 'shared' }] }))
  await startIn($, on, 'git@github.com:alert-d/alertd-core.git')
  expect(registered).toContain('set_topic')
  const compose = (tools: string[]) =>
    $.prompt.compose({ model: 'claude-fable-5-1', promptModel: 'claude-fable-5-1', surfaces: [], tools, outputStyle: null, traits: [] })
  const withTool = await compose(['Bash', TOPIC_TOOL])
  expect(withTool.sections.map(s => s.id)).toEqual(['intro', 'work-band:topic'])
  expect(withTool.sections[1]!.text).toBe(TOPIC_PROMPT)
  expect(withTool.sections[1]!.scope).toBe('session')
  const without = await compose(['Bash'])
  expect(without.sections.map(s => s.id)).toEqual(['intro'])
})

for (const surface of ['terminal', 'desktop'] as const) {
  test(`set_topic draws the labels on the band, after the Jira part (${surface})`, async ($, on) => {
    on('tool.list', () => ({ value: [] }) as never)
    on('tool.check', () => ({ decision: 'allow' }) as never)
    await startIn($, on, 'git@github.com:alert-d/alertd-core.git', '', mock.clock(on), true)
    const ui = await mountBand($, surface)
    const row = async () => (await ui.findAll({ type: 'Box' }))[1]!.text
    expect(await row()).toContain('no Jira key   [ server :1776 ^ ]')

    const bad = await $.tool.call({ tool: TOPIC_TOOL, topics: 'x' } as never)
    expect('deny' in bad && bad.deny).toContain('set_topic takes')
    expect(await row()).toContain('no Jira key   [ server :1776 ^ ]')

    const ok = await $.tool.call({ tool: TOPIC_TOOL, topics: ['work-band topic', ' tests '] } as never)
    expect(ok).toEqual({ result: { topics: ['work-band topic', 'tests'] }, text: 'The band shows: work-band topic · tests' })
    expect(await row()).toContain('no Jira key   work-band topic · tests   [ server :1776 ^ ]')

    await $.tool.call({ tool: TOPIC_TOOL, topics: ['port picking'] } as never)
    expect(await row()).toContain('no Jira key   port picking   [ server :1776 ^ ]')
  })
}

test('the topic counts toward the first row, so a long one moves Jira to its own row', () => {
  const pr = { number: 1, state: 'open', isDraft: false, passed: 1, failed: 0, pending: 0, title: 't' }
  const base = firstRowWidth({ pr, diff: null, jira: { key: 'AL-1', title: 'Short' }, serve: '', plan: undefined })
  expect(firstRowWidth({ pr, diff: null, jira: { key: 'AL-1', title: 'Short' }, serve: '', plan: undefined, topic: 'a · b' })).toBe(base + 3 + 'a · b'.length)
})

test('ports tried: the remembered one, then 1920-1990 in a random order', () => {
  const all = Array.from({ length: 71 }, (_, i) => 1920 + i)
  const ports = candidatePorts(1776)
  expect(ports[0]).toBe(1776)
  expect([...ports.slice(1)].sort((a, b) => a - b)).toEqual(all)
  // A remembered port inside the range is not tried twice.
  const inRange = candidatePorts(1950)
  expect(inRange[0]).toBe(1950)
  expect(inRange.length).toBe(71)
  expect(new Set(inRange).size).toBe(71)
  // The order follows the random source: a different source, a different order.
  let seed = 7
  const lcg = () => ((seed = (seed * 48271) % 2147483647) / 2147483647)
  const a = candidatePorts(1776, lcg)
  const b = candidatePorts(1776, () => 0)
  expect(a).not.toEqual(b)
  expect(b.slice(1)).not.toEqual(all)
})

test('a taken port at session start moves the server to the first free one, for this session', async ($, on) => {
  const taken = new Set(['1776', '1791'])
  const toasts: string[] = []
  on('ui.toast', (_$, e) => {
    toasts.push(e.text)
    return { value: undefined } as never
  })
  const store = new Map<string, unknown>()
  await startIn($, on, 'git@github.com:alert-d/alertd-core.git', '', mock.clock(on), false, store, argv => {
    if (argv[0] !== 'lsof') return undefined
    const at = argv.find(a => a.startsWith('-iTCP:'))!.slice('-iTCP:'.length)
    return taken.has(at) ? '4242\n' : undefined // undefined: lsof exits 1, nothing listening
  })
  const band = await mountBand($, 'terminal')
  const text = (await band.find({ key: 'port' }))?.text ?? ''
  const at = Number(text.slice(1))
  expect(text).toMatch(/^:19\d\d$/)
  expect(at).toBeGreaterThanOrEqual(1920)
  expect(at).toBeLessThanOrEqual(1990)
  expect(toasts).toEqual([`Port 1776 is in use; the server will use ${at}`])
  expect(store.has('port')).toBe(false)
})

test('a free remembered port is kept, with no notice', async ($, on) => {
  const toasts: string[] = []
  on('ui.toast', (_$, e) => {
    toasts.push(e.text)
    return { value: undefined } as never
  })
  await startIn($, on, 'git@github.com:alert-d/alertd-core.git', '', mock.clock(on), false, new Map([['port', 1791]]))
  const band = await mountBand($, 'terminal')
  expect((await band.find({ key: 'port' }))?.text).toBe(':1791')
  expect(toasts).toEqual([])
})

test('the account line: plan and org from claude auth status', () => {
  // As `claude auth status` printed it, trimmed.
  const team = JSON.stringify({ loggedIn: true, authMethod: 'claude.ai', orgName: 'AlertD', subscriptionType: 'team', email: 'adrian@alertd.ai' })
  expect(parseAuthStatus(team)).toEqual({ plan: 'Team', org: 'AlertD', email: 'adrian@alertd.ai' })
  expect(parseAuthStatus(JSON.stringify({ loggedIn: true, authMethod: 'claude.ai', subscriptionType: 'max' }))).toEqual({
    plan: 'Max',
    org: undefined,
    email: undefined,
  })
  expect(parseAuthStatus(JSON.stringify({ loggedIn: true, authMethod: 'api_key' }))).toEqual({ plan: 'API key', org: undefined })
  expect(parseAuthStatus(JSON.stringify({ loggedIn: false }))).toEqual({ plan: 'signed out' })
  expect(parseAuthStatus('not json')).toBe(null)
})

test('the band ends with the plan alone, not the org', async ($, on) => {
  await startIn($, on, 'git@github.com:alert-d/alertd-core.git', '', mock.clock(on), false, new Map(), argv =>
    argv.join(' ') === 'claude auth status'
      ? JSON.stringify({ loggedIn: true, authMethod: 'claude.ai', orgName: 'AlertD', subscriptionType: 'team' })
      : undefined,
  )
  const band = await mountBand($, 'terminal')
  expect((await band.findAll({ type: 'Box' }))[1]!.text).toMatch(/ {3}Team$/)
})
