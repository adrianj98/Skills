import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Account, Check, CheckState, DiffStat, FilesMode, Jira, Pr, Serve, Task } from '../types'
import { ancestorsOf, buildRows, marksOf, parseNameStatus, parseStatus, relativeTo } from './tree'
import type { Change } from './tree'

const pr = atom({ plugin: 'work-band', key: 'pr' } as const, null)
const jira = atom({ plugin: 'work-band', key: 'jira' } as const, null)
const serve = atom({ plugin: 'work-band', key: 'serve' } as const, { state: 'stopped', tasks: [] })
const canServe = atom({ plugin: 'work-band', key: 'canServe' } as const, false)
const isHidden = atom({ plugin: 'work-band', key: 'isHidden' } as const, false)
// The port `t` serves on (WEB_PORT); remembered across sessions in $.store.
const DEFAULT_PORT = 1776
const PORT_CHOICES = ['1776', '1791', '1792']
const port = atom({ plugin: 'work-band', key: 'port' } as const, DEFAULT_PORT)
// What Claude says it is working on now: one to three short labels it sets
// through the set_topic tool; empty until it does.
const topic = atom({ plugin: 'work-band', key: 'topic' } as const, [] as string[])
export const TOPIC_TOOL = 'mcp__work-band__set_topic'
export const TOPIC_MAX = 3
export const TOPIC_PROMPT = `The work band above the prompt shows what you are working on. Call ${TOPIC_TOOL} with one to three short labels (two to four words each) when you start on something and whenever the topic changes: a new feature, a different bug, another area of the code. Do not call it when the topic is unchanged.`
// The Files pane: which view, which folders the person opened (All) or
// closed (PR, Uncommitted), a tick when the file lists change, and the
// spinner frame of the file being edited.
const filesMode = atom({ plugin: 'work-band', key: 'filesMode' } as const, 'pr' as FilesMode)
const openDirs = atom({ plugin: 'work-band', key: 'openDirs' } as const, [] as string[])
const closedDirs = atom({ plugin: 'work-band', key: 'closedDirs' } as const, [] as string[])
const filesTick = atom({ plugin: 'work-band', key: 'filesTick' } as const, 0)
const editFrame = atom({ plugin: 'work-band', key: 'editFrame' } as const, 0)
// Lines this branch adds and removes against its PR's base, or develop.
const diffStat = atom({ plugin: 'work-band', key: 'diffStat' } as const, null as DiffStat | null)
// Runs whose re-run was asked for, until a refresh shows them going again.
const rerunAsked = atom({ plugin: 'work-band', key: 'rerunAsked' } as const, [] as string[])
// Which Claude Code account the session runs as, from `claude auth status`.
const account = atom({ plugin: 'work-band', key: 'account' } as const, null as Account | null)
// PRs whose merge this session already told the model about.
const mergedTold = atom({ plugin: 'work-band', key: 'mergedTold' } as const, [] as number[])
// Which task's logs the pane shows; `tick` changes to redraw it.
const logView = atom({ plugin: 'work-band', key: 'logView' } as const, { task: '', tick: 0 })

// `t` is the shell alias `npx turbo run serve --ui=tui`. The TUI needs a
// terminal, which a spawned child has none of, so it streams instead.
// The button runs alertd-core's server, so it shows only in that repo.
const SERVE_REPO = /[:/]alert-d\/alertd-core(\.git)?$/
const SERVE_ARGV = ['npx', 'turbo', 'run', 'serve', '--ui=stream']
const DRY_ARGV = ['npx', 'turbo', 'run', 'serve', '--dry=json']
// Whichever Jira MCP server is connected: claude.ai's "Atlassian Rovo", its
// older "Atlassian", a local `atlassian` server. Every one serves getJiraIssue.
export const pickJiraTool = (names: readonly string[], op = 'getJiraIssue'): string | undefined =>
  names.find(n => new RegExp(`^mcp__.+__${op}$`).test(n))

// Plain text of the band's first row, as wide as it is drawn, so the Jira
// part can move to a row of its own when the row would not fit `columns`.
export const firstRowWidth = (parts: { pr: Pr | null; diff: DiffStat | null; jira: Jira | null; serve: string; plan: string | undefined; topic?: string }): number => {
  const { pr: p, diff: d, jira: j } = parts
  const diffText = d ? `+${d.added} −${d.removed}${p ? '' : ` vs ${d.base}`}` : 'diff'
  const prText = p
    ? `PR #${p.number} ${p.isDraft ? 'draft' : p.state} · ${diffText} · ✓${p.passed} ✗${p.failed} …${p.pending}`
    : `no PR · ${diffText}`
  const jiraText = j ? `${j.key} ${'title' in j ? `${j.status ? `${j.status} ` : ''}${j.title}` : j.error}` : 'no Jira key'
  return prText.length + 3 + jiraText.length + (parts.topic ? 3 + parts.topic.length : 0) + parts.serve.length + (parts.plan ? 3 + parts.plan.length : 0)
}

// The labels the model handed set_topic, trimmed, blanks dropped, at most
// TOPIC_MAX; undefined when the input is not a list of strings.
export const parseTopics = (input: unknown): string[] | undefined => {
  const list = (input as { topics?: unknown } | null)?.topics
  if (!Array.isArray(list) || !list.every(t => typeof t === 'string')) return undefined
  return (list as string[]).map(t => t.trim()).filter(t => t !== '').slice(0, TOPIC_MAX)
}
export const topicText = (topics: readonly string[]): string => topics.join(' · ')

// `text` cut to `width` cells with an ellipsis, whole when it fits.
export const fitWidth = (text: string, width: number): string =>
  text.length <= width ? text : width <= 1 ? '…' : `${text.slice(0, width - 1)}…`

// The issue's summary from getJiraIssue's JSON, JSON escapes undone.
export const parseJiraTitle = (text: string): string | undefined => {
  const raw = text.match(/"summary"\s*:\s*"((?:[^"\\]|\\.)*)"/)?.[1]
  if (!raw) return undefined
  try {
    return JSON.parse(`"${raw}"`) as string
  } catch {
    return raw
  }
}
// The issue's status name from getJiraIssue's JSON: `"status":{...,"name":"To Do",...}`.
export const parseJiraStatus = (text: string): string | undefined => {
  const raw = text.match(/"status"\s*:\s*\{[^{}]*?"name"\s*:\s*"((?:[^"\\]|\\.)*)"/)?.[1]
  if (!raw) return undefined
  try {
    return JSON.parse(`"${raw}"`) as string
  } catch {
    return raw
  }
}

// The transitions getTransitionsForJiraIssue offers, unavailable ones left out.
export const parseTransitions = (text: string): { id: string; name: string; to: string }[] => {
  try {
    const raw = (JSON.parse(text) as { transitions?: unknown }).transitions
    if (!Array.isArray(raw)) return []
    return raw.flatMap((t: { id?: unknown; name?: unknown; isAvailable?: unknown; to?: { name?: unknown } }) =>
      typeof t.id === 'string' && typeof t.name === 'string' && t.isAvailable !== false
        ? [{ id: t.id, name: t.name, to: typeof t.to?.name === 'string' ? t.to.name : t.name }]
        : [],
    )
  } catch {
    return []
  }
}

// The picker holds at most four options: a longer list is shown three at a
// time with `More…` last, and the final page up to four.
export const MORE = 'More…'
export const transitionPage = (names: readonly string[], page: number): string[] => {
  const start = page * 3
  const rest = names.slice(start)
  return rest.length <= 4 ? [...rest] : [...rest.slice(0, 3), MORE]
}

// The common Jira statuses by name; any other is its words' initials, or
// its first four letters when it is one word.
const STATUS_ABBREVIATIONS: Record<string, string> = {
  'to do': 'TODO',
  'in progress': 'PROG',
  'in review': 'REV',
  'code review': 'REV',
  'in testing': 'TEST',
  'ready for review': 'RFR',
  'ready for test': 'RFT',
  'ready for dev': 'RFD',
  'selected for development': 'SEL',
  backlog: 'BKLG',
  blocked: 'BLKD',
  'on hold': 'HOLD',
  done: 'DONE',
  closed: 'CLSD',
  resolved: 'RSLV',
  reopened: 'REOP',
  open: 'OPEN',
  cancelled: 'CANC',
  canceled: 'CANC',
}

export const abbreviateStatus = (name: string): string => {
  const words = name.trim().split(/\s+/).filter(Boolean)
  if (words.length === 0) return ''
  const known = STATUS_ABBREVIATIONS[words.join(' ').toLowerCase()]
  if (known) return known
  if (words.length > 1) return words.map(w => w.charAt(0)).join('').toUpperCase()
  return words[0]!.slice(0, 4).toUpperCase()
}
const JIRA_SITE = 'alertd.atlassian.net'

export const jiraUrl = (key: string) => `https://${JIRA_SITE}/browse/${key}`
const POLL_MS = 120_000
const MIN_PR_GAP_MS = 30_000

const ANSI = /\u001b\[[0-9;?]*[ -/]*[@-~]/g
const ISSUE_KEY = /\b[A-Z][A-Z0-9]+-\d+\b/

// One entry of `gh pr view --json statusCheckRollup`: a CheckRun (name,
// status, conclusion, detailsUrl) or a StatusContext (context, state, targetUrl).
type RawCheck = {
  name?: string
  context?: string
  workflowName?: string
  status?: string | null
  conclusion?: string | null
  state?: string | null
  startedAt?: string | null
  completedAt?: string | null
  detailsUrl?: string | null
  targetUrl?: string | null
}

export const verdictOf = (c: RawCheck): CheckState => {
  const verdict = (c.conclusion || c.state || '').toUpperCase()
  if (c.status && c.status !== 'COMPLETED') return 'pending'
  if (verdict === 'SUCCESS') return 'pass'
  if (['FAILURE', 'CANCELLED', 'TIMED_OUT', 'ERROR', 'ACTION_REQUIRED', 'STARTUP_FAILURE'].includes(verdict)) return 'fail'
  if (verdict === 'PENDING' || verdict === 'EXPECTED' || verdict === '') return 'pending'
  return 'skipped' // SKIPPED, NEUTRAL, STALE
}

const CHECK_ORDER: Record<CheckState, number> = { fail: 0, pending: 1, pass: 2, skipped: 3 }

// The checks as the pane lists them: failures first, then running, passed, skipped.
export const toChecks = (raw: readonly RawCheck[]): Check[] =>
  raw
    .map(
      (c): Check => ({
        name: c.name ?? c.context ?? '?',
        workflow: c.workflowName || undefined,
        state: verdictOf(c),
        startedAt: c.startedAt && !c.startedAt.startsWith('0001') ? c.startedAt : undefined,
        completedAt: c.completedAt && !c.completedAt.startsWith('0001') ? c.completedAt : undefined,
        url: c.detailsUrl ?? c.targetUrl ?? undefined,
      }),
    )
    .sort((a, b) => CHECK_ORDER[a.state] - CHECK_ORDER[b.state] || a.name.localeCompare(b.name))

export const countChecks = (raw: readonly RawCheck[]) => {
  const states = raw.map(verdictOf)
  return {
    passed: states.filter(s => s === 'pass').length,
    failed: states.filter(s => s === 'fail').length,
    pending: states.filter(s => s === 'pending').length,
  }
}

// ` 31 files changed, 455 insertions(+), 444 deletions(-)`; either count is
// left out when it is zero, and an empty diff prints nothing.
export const parseShortstat = (text: string): { added: number; removed: number } => ({
  added: Number(text.match(/(\d+) insertions?\(\+\)/)?.[1] ?? 0),
  removed: Number(text.match(/(\d+) deletions?\(-\)/)?.[1] ?? 0),
})

// A check's GitHub Actions run and job, from its details link:
// https://github.com/<owner>/<repo>/actions/runs/<run>/job/<job>. The job
// number there is the databaseId `gh run rerun --job` takes.
export const runOf = (url: string | undefined): { run: string; job?: string } | undefined => {
  const m = url?.match(/\/actions\/runs\/(\d+)(?:\/job\/(\d+))?/)
  return m ? { run: m[1]!, job: m[2] } : undefined
}

// The gh command that re-runs one check: a failed job alone; a skipped one
// (never ran) only runs again with its whole run, so the run.
export const rerunOne = (c: Check): string[] | undefined => {
  const at = runOf(c.url)
  if (!at) return undefined
  if (c.state === 'fail') return at.job ? ['gh', 'run', 'rerun', at.run, '--job', at.job] : ['gh', 'run', 'rerun', at.run, '--failed']
  if (c.state === 'skipped') return ['gh', 'run', 'rerun', at.run]
  return undefined
}

// Every failed or skipped check, one gh command per run: the whole run when
// any of its jobs was skipped (that also re-runs its failures), else only its
// failed jobs. A run still going is left alone; gh refuses it.
export const rerunAll = (checks: readonly Check[]): string[][] => {
  const runs = new Map<string, CheckState[]>()
  for (const c of checks) {
    const at = runOf(c.url)
    if (at) runs.set(at.run, [...(runs.get(at.run) ?? []), c.state])
  }
  return [...runs]
    .filter(([, states]) => !states.includes('pending'))
    .flatMap(([run, states]) =>
      states.includes('skipped')
        ? [['gh', 'run', 'rerun', run]]
        : states.includes('fail')
          ? [['gh', 'run', 'rerun', run, '--failed']]
          : [],
    )
}

// `claude auth status` prints JSON: { loggedIn, authMethod, orgName,
// subscriptionType: "team" | "max" | "pro" | ..., email }.
export const parseAuthStatus = (text: string): Account | null => {
  let raw: { loggedIn?: boolean; authMethod?: string; subscriptionType?: string; orgName?: string; email?: string }
  try {
    raw = JSON.parse(text)
  } catch {
    return null
  }
  if (!raw.loggedIn) return { plan: 'signed out' }
  if (raw.authMethod !== 'claude.ai') return { plan: 'API key', org: raw.orgName || undefined }
  const plan = raw.subscriptionType ? raw.subscriptionType[0]!.toUpperCase() + raw.subscriptionType.slice(1) : 'claude.ai'
  return { plan, org: raw.orgName || undefined, email: raw.email || undefined }
}

// 1h 02m · 4m 31s · 12s
export const formatDuration = (ms: number): string => {
  const sec = Math.max(0, Math.round(ms / 1000))
  const h = Math.floor(sec / 3600)
  const m = Math.floor((sec % 3600) / 60)
  const s = sec % 60
  if (h) return `${h}h ${String(m).padStart(2, '0')}m`
  if (m) return `${m}m ${String(s).padStart(2, '0')}s`
  return `${s}s`
}

// Turbo has no live per-task status, so it is read off the stream, whose
// lines turbo 2.11 prefixes with the task:
//   //:serve: cache bypass, force executing <hash>     the task started
//   //#bad:  ERROR  command (...) npm run bad exited (3)  it failed
// A one-shot task (kill-port) prints nothing when it succeeds; it is done
// once a task depending on it starts, or the whole run exits 0.
const STARTED = /^[^:\s]+:(\S+?): cache (?:bypass|miss|hit)/
const FAILED = /^[^#\s]+#(\S+?):\s+ERROR\s+command .*exited \((\d+)\)/

const OUTPUT = /^[^:\s]+:(\S+?): /

// A port typed or picked in the menu: a whole number from 1 to 65535.
export const parsePort = (text: string): number | undefined => {
  const n = Number(text.trim())
  return text.trim() !== '' && Number.isInteger(n) && n >= 1 && n <= 65535 ? n : undefined
}

// The ports tried, in order, when the remembered one is taken: the remembered
// one first, then 1920-1990 in a random order (`random` is Math.random; a
// test passes its own).
export const RANDOM_PORTS = { from: 1920, to: 1990 } as const
export const candidatePorts = (preferred: number, random: () => number = Math.random): number[] => {
  const pool = Array.from({ length: RANDOM_PORTS.to - RANDOM_PORTS.from + 1 }, (_, i) => RANDOM_PORTS.from + i)
  for (let i = pool.length - 1; i > 0; i--) {
    const j = Math.floor(random() * (i + 1))
    ;[pool[i], pool[j]] = [pool[j]!, pool[i]!]
  }
  return [preferred, ...pool.filter(at => at !== preferred)]
}

const taskName = (taskId: string) => taskId.replace(/^.*#/, '')

// The task a stream line was printed by, if it carries turbo's prefix.
export const taskOfLine = (line: string): string | undefined => line.replace(ANSI, '').match(OUTPUT)?.[1]

// The tasks `turbo run serve --dry=json` plans, dependencies first.
export const parseDry = (json: string): Task[] => {
  const raw = JSON.parse(json) as {
    tasks: { taskId: string; dependencies?: string[]; resolvedTaskDefinition?: { persistent?: boolean } }[]
  }
  return raw.tasks
    .map(
      (t): Task => ({
        name: taskName(t.taskId),
        state: 'pending',
        persistent: Boolean(t.resolvedTaskDefinition?.persistent),
        deps: (t.dependencies ?? []).map(taskName),
      }),
    )
    .sort((a, b) => a.deps.length - b.deps.length || a.name.localeCompare(b.name))
}

const upsert = (tasks: readonly Task[], name: string, change: (t: Task) => Task): Task[] =>
  tasks.some(t => t.name === name)
    ? tasks.map(t => (t.name === name ? change(t) : t))
    : [...tasks, change({ name, state: 'pending', persistent: false, deps: [] })]

export const applyLine = (tasks: readonly Task[], rawLine: string): readonly Task[] => {
  const line = rawLine.replace(ANSI, '')
  const failed = line.match(FAILED)
  if (failed) return upsert(tasks, failed[1]!, t => ({ ...t, state: 'failed', code: Number(failed[2]) }))
  const started = line.match(STARTED)
  if (!started) return tasks
  const name = started[1]!
  const next = upsert(tasks, name, t => ({ ...t, state: 'running' }))
  const deps = next.find(t => t.name === name)!.deps
  return next.map(t => (deps.includes(t.name) && t.state !== 'failed' ? { ...t, state: 'done' } : t))
}

// The run is over: a clean exit finished the one-shot tasks; anything else
// still marked running was stopped with it.
export const finishTasks = (tasks: readonly Task[], code: number | null): Task[] =>
  tasks.map(t =>
    t.state === 'running' || t.state === 'pending'
      ? { ...t, state: code === 0 && !t.persistent && t.state === 'running' ? 'done' : 'stopped' }
      : t,
  )

// Planned tasks first, in plan order, with what the stream already showed.
export const mergePlan = (plan: readonly Task[], seen: readonly Task[]): Task[] => [
  ...plan.map(p => {
    const s = seen.find(t => t.name === p.name)
    return s ? { ...p, state: s.state, code: s.code } : p
  }),
  ...seen.filter(t => !plan.some(p => p.name === t.name)),
]

const TASK_MARK: Record<Task['state'], string> = {
  pending: '○',
  running: '●',
  done: '✓',
  failed: '✗',
  stopped: '■',
}
const TASK_COLOR: Record<Task['state'], 'success' | 'error' | 'subtle' | undefined> = {
  pending: undefined,
  running: 'success',
  done: 'subtle',
  failed: 'error',
  stopped: undefined,
}

// $.state outlives a reload: a Serve saved by an older version of this mod
// has no `tasks`, and reading it as an array would blank the whole band.
const tasksOf = (s: Serve): readonly Task[] => s.tasks ?? []

// Each task's recent output, for the logs pane. Kept in the module, not in
// $.state: it changes on every line and only the pane reads it.
const LOGS_PANE = 'server-logs'
const LOG_LINES = 500
const LOG_REDRAW_MS = 250
const logs = new Map<string, string[]>()
let logRedrawAt = -Infinity

export const keepLines = (kept: readonly string[], lines: readonly string[], max: number): string[] =>
  [...kept, ...lines].slice(-max)

// `//:serve: listening on 1776` → `listening on 1776`
export const withoutPrefix = (line: string): string => line.replace(ANSI, '').replace(OUTPUT, '')

async function recordLogs($: EngineInterface, lines: readonly string[]) {
  const byTask = new Map<string, string[]>()
  for (const line of lines) {
    const task = taskOfLine(line)
    if (task) byTask.set(task, [...(byTask.get(task) ?? []), withoutPrefix(line)])
  }
  for (const [task, added] of byTask) logs.set(task, keepLines(logs.get(task) ?? [], added, LOG_LINES))

  const view = await read($, logView)
  const now = await $.clock.now()
  if (byTask.has(view.task) && now - logRedrawAt >= LOG_REDRAW_MS) {
    logRedrawAt = now
    await update($, logView, v => ({ ...v, tick: v.tick + 1 }))
  }
}

async function toggleLogs($: EngineInterface, task: string) {
  const view = await read($, logView)
  const isOpen = (await $.ui.panes()).some(pane => pane.id === LOGS_PANE)
  if (isOpen && view.task === task) return $.ui.close({ id: LOGS_PANE })
  await update($, logView, v => ({ task, tick: v.tick + 1 }))
  await $.ui.open({ id: LOGS_PANE, title: `${task} logs`, closeOnEscape: true })
}

const FILES_PANE = 'files'
const EDIT_TOOLS = new Set(['Edit', 'Write', 'MultiEdit', 'NotebookEdit'])
const SPINNER = '⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
const EDIT_LINGER_MS = 1500

// Kept in the module, not $.state: the repo's 12k paths would be copied on
// every write. `filesTick` redraws the pane when they change.
let repoTop = ''
let allFiles: string[] = []
let prChanges: Change[] = []
let uncommitted: Change[] = []
const editing = new Map<string, number>() // path → how many edits are in flight
let spinTimer: { cancel: () => void } | null = null

async function refreshFiles($: EngineInterface) {
  const top = await $.process.run(['git', 'rev-parse', '--show-toplevel'])
  if (top.exitCode !== 0) return
  repoTop = top.stdout.trim()
  const base = (await read($, pr))?.base ?? 'develop'
  const [ls, status, diff] = await Promise.all([
    $.process.run(['git', '-C', repoTop, 'ls-files']),
    $.process.run(['git', '-C', repoTop, 'status', '--porcelain=v1', '-uall']),
    $.process.run(['git', '-C', repoTop, 'diff', '--name-status', `origin/${base}...HEAD`]),
  ])
  allFiles = ls.exitCode === 0 ? ls.stdout.split('\n').filter(Boolean) : []
  uncommitted = status.exitCode === 0 ? parseStatus(status.stdout) : []
  prChanges = diff.exitCode === 0 ? parseNameStatus(diff.stdout) : []
  await update($, filesTick, n => n + 1)
}

async function isFilesOpen($: EngineInterface) {
  return (await $.ui.panes()).some(pane => pane.id === FILES_PANE)
}

// The filetree mod (data-goblin/claude-code-filetree), when it is installed:
// its /filetree command opens its own pane, which this mod can neither list
// nor close, so the Files button opens or refocuses it rather than toggling.
async function hasFiletree($: EngineInterface) {
  try {
    return (await $.command.list()).some(c => c.name === 'filetree')
  } catch {
    return false
  }
}

async function toggleFiles($: EngineInterface) {
  if (await hasFiletree($)) {
    const { text } = await $.command.run({ command: 'filetree' })
    // filetree answers a refusal (no fullscreen layout, a narrow terminal) as text.
    if (text && !/^File tree on /.test(text)) $.ui.toast(text)
    return
  }
  if (await isFilesOpen($)) return $.ui.close({ id: FILES_PANE })
  await $.ui.open({ id: FILES_PANE, title: 'Files', closeOnEscape: true })
  await refreshFiles($)
}

async function toggleDir($: EngineInterface, dir: string) {
  const flip = (dirs: string[]) => (dirs.includes(dir) ? dirs.filter(d => d !== dir) : [...dirs, dir])
  if ((await read($, filesMode)) === 'all') await update($, openDirs, flip)
  else await update($, closedDirs, flip)
}

async function startEdit($: EngineInterface, path: string) {
  editing.set(path, (editing.get(path) ?? 0) + 1)
  spinTimer ??= $.clock.every(120, () => void update($, editFrame, f => f + 1).catch(() => {}))
  await update($, editFrame, f => f + 1) // show it now, not at the first tick
}

async function endEdit($: EngineInterface, path: string) {
  const left = (editing.get(path) ?? 1) - 1
  if (left > 0) editing.set(path, left)
  else editing.delete(path)
  if (editing.size === 0 && spinTimer) {
    spinTimer.cancel()
    spinTimer = null
    await update($, editFrame, f => f + 1)
  }
  if (await isFilesOpen($)) await refreshFiles($)
}

const CHECKS_PANE = 'pr-checks'

async function toggleChecks($: EngineInterface) {
  if ((await $.ui.panes()).some(pane => pane.id === CHECKS_PANE)) return $.ui.close({ id: CHECKS_PANE })
  const current = await read($, pr)
  await $.ui.open({ id: CHECKS_PANE, title: current ? `PR #${current.number} checks` : 'PR checks', closeOnEscape: true })
  void refreshAll($) // the pane shows what gh says now; a merge it sees is told
}

const MARK_COLOR = { pr: 'suggestion', uncommitted: 'warning' } as const

async function rerun($: EngineInterface, commands: readonly string[][], what: string) {
  const runs = commands.map(argv => argv[3]!)
  await update($, rerunAsked, asked => [...new Set([...asked, ...runs])])
  const results = await Promise.all(commands.map(argv => $.process.run(argv)))
  const failed = results.find(r => r.exitCode !== 0)
  if (failed) {
    $.ui.toast(`Re-run of ${what} failed: ${(failed.stderr || failed.stdout).trim().split('\n')[0]}`)
    await update($, rerunAsked, asked => asked.filter(r => !runs.includes(r)))
    return
  }
  $.ui.toast(`Re-run started: ${what}`)
  $.clock.after(5_000, () => void refreshAll($)) // pick up the new attempt
}

const CHECK_MARK: Record<CheckState, string> = { fail: '✗', pending: '…', pass: '✓', skipped: '–' }
const CHECK_COLOR: Record<CheckState, 'error' | 'warning' | 'success' | 'subtle'> = {
  fail: 'error',
  pending: 'warning',
  pass: 'success',
  skipped: 'subtle',
}

// A running task's dot lights up while it prints, and dims FLASH_MS after.
const FLASH_MS = 400
const flashTimers = new Map<string, { cancel: () => void }>()

const setFlash = (tasks: readonly Task[], names: ReadonlySet<string>, isOn: boolean): Task[] =>
  tasks.map(t => (names.has(t.name) ? { ...t, flash: isOn } : t))

async function flash($: EngineInterface, names: ReadonlySet<string>, mine: number) {
  const fresh = new Set([...names].filter(n => !flashTimers.has(n)))
  if (fresh.size) await update($, serve, (s): Serve => ({ ...s, tasks: setFlash(tasksOf(s), fresh, true) }))
  for (const name of names) {
    flashTimers.get(name)?.cancel()
    flashTimers.set(
      name,
      $.clock.after(FLASH_MS, () => {
        flashTimers.delete(name)
        if (mine !== generation) return
        void update($, serve, (s): Serve => ({ ...s, tasks: setFlash(tasksOf(s), new Set([name]), false) })).catch(() => {})
      }),
    )
  }
}

let child: AsyncGenerator<unknown, unknown> | null = null
let generation = 0
let lastPrFetch = 0
let plan: Task[] | null = null

async function refreshPr($: EngineInterface): Promise<Pr | null> {
  lastPrFetch = await $.clock.now()
  const { exitCode, stdout } = await $.process.run([
    'gh', 'pr', 'view', '--json',
    'number,state,isDraft,statusCheckRollup,title,baseRefName,url',
  ])
  if (exitCode !== 0) {
    await update($, pr, () => null)
    return null
  }
  const raw = JSON.parse(stdout)
  const next: Pr = {
    number: raw.number,
    state: String(raw.state).toLowerCase(),
    isDraft: Boolean(raw.isDraft),
    title: raw.title ?? '',
    ...countChecks(raw.statusCheckRollup ?? []),
    checks: toChecks(raw.statusCheckRollup ?? []),
    base: raw.baseRefName || undefined,
    url: raw.url || undefined,
  }
  await update($, pr, () => next)
  const going = new Set(next.checks?.filter(c => c.state === 'pending').map(c => runOf(c.url)?.run))
  await update($, rerunAsked, asked => asked.filter(run => !going.has(run)))
  return next
}

async function refreshJira($: EngineInterface, current: Pr | null) {
  const branch = (await $.process.run(['git', 'branch', '--show-current'])).stdout.trim()
  const key = (current?.title.match(ISSUE_KEY) ?? branch.match(ISSUE_KEY))?.[0]
  if (!key) {
    await update($, jira, () => null)
    return
  }
  const tool = pickJiraTool((await $.tool.list()).map(t => t.name))
  if (!tool) {
    await update($, jira, (): Jira => ({ key, error: 'no Jira MCP connected' }))
    return
  }
  const input = { tool, cloudId: JIRA_SITE, issueIdOrKey: key, fields: ['summary', 'status'] }
  // A refresh every two minutes must never open a permission dialog.
  const { decision } = await $.tool.check({ tool, input })
  if (decision !== 'allow') {
    await update($, jira, (): Jira => ({ key, error: `allow ${tool} to show the title` }))
    return
  }
  const result = await $.tool.call(input as never)
  const text = 'text' in result && typeof result.text === 'string' ? result.text : ''
  const title = parseJiraTitle(text)
  const statusName = parseJiraStatus(text)
  const status = statusName ? abbreviateStatus(statusName) : undefined
  await update($, jira, (): Jira => (title ? (status ? { key, title, status } : { key, title }) : { key, error: 'no title' }))
}

// Clicking the status: the issue's transitions in a picker, the chosen one
// applied, the band refreshed. A click may open the tools' permission dialog.
async function changeJiraStatus($: EngineInterface) {
  const j = await read($, jira)
  if (!j || !('title' in j)) return
  const names = (await $.tool.list()).map(t => t.name)
  const list = pickJiraTool(names, 'getTransitionsForJiraIssue')
  const move = pickJiraTool(names, 'transitionJiraIssue')
  if (!list || !move) {
    $.ui.toast('The Jira MCP cannot change statuses')
    return
  }
  const got = await $.tool.call({ tool: list, cloudId: JIRA_SITE, issueIdOrKey: j.key } as never)
  if ('deny' in got) {
    $.ui.toast(`Could not list ${j.key}'s statuses: ${got.deny}`)
    return
  }
  const all = parseTransitions('text' in got && typeof got.text === 'string' ? got.text : '')
  const options = all.filter(t => abbreviateStatus(t.to) !== j.status)
  if (options.length === 0) {
    $.ui.toast(`No status changes offered for ${j.key}`)
    return
  }
  let choice: string = MORE
  for (let page = 0; choice === MORE; page++) {
    try {
      choice = await $.ui.ask(`Move ${j.key} to which status?`, {
        header: 'Jira',
        options: transitionPage(
          options.map(t => t.name),
          page,
        ),
      })
    } catch {
      return // dismissed
    }
  }
  const picked = options.find(t => t.name.toLowerCase() === choice.trim().toLowerCase())
  if (!picked) {
    $.ui.toast(`"${choice}" is not a status ${j.key} can move to`)
    return
  }
  const done = await $.tool.call({ tool: move, cloudId: JIRA_SITE, issueIdOrKey: j.key, transition: { id: picked.id } } as never)
  if ('deny' in done || done.isError) {
    $.ui.toast(`${j.key} was not moved: ${('deny' in done ? done.deny : done.text) ?? ''}`.trim())
    return
  }
  $.ui.toast(`${j.key} → ${picked.to}`)
  await refreshJira($, await read($, pr))
}

async function checkRepo($: EngineInterface) {
  const { exitCode, stdout } = await $.process.run(['git', 'remote', 'get-url', 'origin'])
  await update($, canServe, () => exitCode === 0 && SERVE_REPO.test(stdout.trim()))
}

// The model is told only of a merge this session saw happen (open, then
// merged), never of a PR that was already merged when the session started.
export const mergePrompt = (prNumber: number, title: string, jiraKey: string | undefined): string =>
  [
    `PR #${prNumber} ("${title}") has just been merged; the work-band mod saw it change from open to merged.`,
    jiraKey
      ? `Its Jira issue is ${jiraKey}. Update ${jiraKey} for the merge, following this project's Jira rules.`
      : 'No Jira issue key was found in the PR title or the branch name; ask which issue to update.',
  ].join(' ')

async function tellIfMerged($: EngineInterface, before: Pr | null, after: Pr | null) {
  if (!before || !after || before.number !== after.number) return
  if (before.state !== 'open' || after.state !== 'merged') return
  let isNew = false
  await update($, mergedTold, told => (told.includes(after.number) ? told : ((isNew = true), [...told, after.number])))
  if (!isNew) return
  const branch = (await $.process.run(['git', 'branch', '--show-current'])).stdout.trim()
  const key = (after.title.match(ISSUE_KEY) ?? branch.match(ISSUE_KEY))?.[0]
  $.ui.toast(`PR #${after.number} merged`)
  void $.prompt.submit({ text: mergePrompt(after.number, after.title, key) })
}

async function refreshDiff($: EngineInterface, current: Pr | null) {
  const base = current?.base ?? 'develop'
  const { exitCode, stdout } = await $.process.run(['git', 'diff', '--shortstat', `origin/${base}...HEAD`])
  await update($, diffStat, (): DiffStat | null => (exitCode === 0 ? { ...parseShortstat(stdout), base } : null))
}

async function refreshAccount($: EngineInterface) {
  const { exitCode, stdout } = await $.process.run(['claude', 'auth', 'status'], { timeoutMs: 15_000 })
  await update($, account, () => (exitCode === 0 ? parseAuthStatus(stdout) : null))
}

async function refreshAll($: EngineInterface) {
  try {
    const before = await read($, pr)
    const current = await refreshPr($)
    await refreshDiff($, current)
    await tellIfMerged($, before, current)
    await refreshJira($, current)
  } catch (err) {
    $.ui.log(`work-band refresh failed: ${String(err)}`, { to: 'debug' })
  }
}

async function stopServe($: EngineInterface) {
  ++generation
  if (child) {
    const old = child
    child = null
    await old.return(undefined) // leaving the stream kills the child
  }
  await update($, serve, (s): Serve => ({ state: 'stopped', tasks: finishTasks(tasksOf(s), null) }))
}

// Chrome's tab already on this server comes to the front, else a new tab
// opens. Matching the origin plus `/` keeps :1776 from matching :17760.
export const CHROME_FOCUS_TAB = `on run argv
  set origin to item 1 of argv
  tell application "Google Chrome"
    repeat with w in windows
      set i to 0
      repeat with t in tabs of w
        set i to i + 1
        set u to URL of t
        if u is origin or u starts with (origin & "/") then
          set active tab index of w to i
          set index of w to 1
          activate
          return "reused"
        end if
      end repeat
    end repeat
    open location origin
    activate
    return "opened"
  end tell
end run`

export const serverUrl = (at: number) => `http://localhost:${at}`

// A Button that opens a URL rather than a Link: a terminal without OSC 8
// draws a Link's URL beside its text, and the band has no room for that.
async function openUrl($: EngineInterface, url: string) {
  await $.process.run(['open', url])
}

async function openServer($: EngineInterface) {
  const url = serverUrl(await read($, port))
  const chrome = await $.process.run(['osascript', '-e', CHROME_FOCUS_TAB, url]).catch(() => null)
  if (chrome?.exitCode === 0) return
  // Not Chrome, or macOS refused the terminal control of it: a plain open.
  await $.process.run(['open', url])
}

// Something is listening on the port (lsof answers its pids, exit 0).
async function isPortTaken($: EngineInterface, at: number) {
  const { exitCode, stdout } = await $.process.run(['lsof', '-nP', `-iTCP:${at}`, '-sTCP:LISTEN', '-t'])
  return exitCode === 0 && stdout.trim() !== ''
}

// At session start: keep the remembered port if it is free, else take a
// random free one in 1920-1990 for this session (the remembered one stays stored).
async function pickFreePort($: EngineInterface) {
  const preferred = await read($, port)
  for (const at of candidatePorts(preferred)) {
    if (await isPortTaken($, at)) continue
    if (at !== preferred) {
      await update($, port, () => at)
      $.ui.toast(`Port ${preferred} is in use; the server will use ${at}`)
    }
    return
  }
}

async function choosePort($: EngineInterface) {
  const current = await read($, port)
  let answer: string
  try {
    answer = await $.ui.ask(`Which port should the server use? It is on ${current} now.`, {
      header: 'port',
      options: PORT_CHOICES,
    })
  } catch {
    return // dismissed
  }
  const chosen = parsePort(answer)
  if (chosen === undefined) {
    $.ui.toast(`"${answer}" is not a port (1-65535)`)
    return
  }
  await update($, port, () => chosen)
  await $.store.set('port', chosen)
  if ((await read($, serve)).state === 'running') await restartServe($)
}

async function openServeMenu($: EngineInterface) {
  const isRunning = (await read($, serve)).state === 'running'
  const at = await read($, port)
  let choice: string
  try {
    choice = isRunning
      ? await $.ui.ask(`The server is running on ${at}. What should happen to it?`, {
          header: 'server',
          options: ['Restart', 'Kill', 'Change port', 'Cancel'],
        })
      : await $.ui.ask(`The server is stopped. Start it on ${at}?`, {
          header: 'server',
          options: ['Start', 'Change port', 'Cancel'],
        })
  } catch {
    return // dismissed
  }
  if (choice === 'Restart' || choice === 'Start') return restartServe($)
  if (choice === 'Kill') return stopServe($)
  if (choice === 'Change port') return choosePort($)
}

async function loadPlan($: EngineInterface, mine: number) {
  if (!plan) {
    const { exitCode, stdout } = await $.process.run(DRY_ARGV, { timeoutMs: 120_000 })
    if (exitCode !== 0) return
    plan = parseDry(stdout)
  }
  const planned = plan
  if (mine === generation) await update($, serve, (s): Serve => ({ ...s, tasks: mergePlan(planned, tasksOf(s)) }))
}

async function restartServe($: EngineInterface) {
  const mine = ++generation
  if (child) {
    const old = child
    child = null
    await old.return(undefined) // leaving the stream kills the child
  }
  logs.clear()
  // ORCHESTRATOR_SINGLETON_GATE=false: skip the Postgres singleton lock, so
  // this server boots beside another worktree's instead of parking behind it
  // (src/server/sessions/bin/orchestratorSingleton.ts; local development only).
  const env = { FORCE_COLOR: '0', WEB_PORT: String(await read($, port)), ORCHESTRATOR_SINGLETON_GATE: 'false' }
  const stream = $.process.spawn({ argv: SERVE_ARGV, env })
  child = stream
  await update($, serve, (): Serve => ({ state: 'running', tasks: plan ?? [] }))
  void loadPlan($, mine).catch(() => {})

  void (async () => {
    let rest = ''
    try {
      let step = await stream.next()
      while (!step.done) {
        const lines = (rest + step.value.text).split(/\r?\n|\r/)
        rest = lines.pop() ?? ''
        if (mine === generation && lines.some(l => STARTED.test(l.replace(ANSI, '')) || FAILED.test(l.replace(ANSI, '')))) {
          await update($, serve, (s): Serve => ({ ...s, tasks: lines.reduce(applyLine, tasksOf(s)) }))
        }
        if (mine === generation) await recordLogs($, lines)
        const printing = new Set(lines.map(taskOfLine).filter((n): n is string => n !== undefined))
        if (mine === generation && printing.size) await flash($, printing, mine)
        step = await stream.next()
      }
      if (mine === generation) {
        child = null
        const { code, signal } = step.value
        await update($, serve, (s): Serve => ({
          state: 'exited',
          code: code ?? null,
          signal: signal ?? undefined,
          tasks: finishTasks(applyLine(tasksOf(s), rest), code),
        }))
      }
    } catch (err) {
      if (mine === generation) {
        child = null
        await update($, serve, (s): Serve => ({ ...s, state: 'exited', code: null, tasks: finishTasks(tasksOf(s), null) }))
        $.ui.log(`work-band: server stream failed: ${String(err)}`, { to: 'debug' })
      }
    }
  })().catch(() => {
    // the module unloaded while the child ran: nothing left to update
  })
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const started = await next(e)
    await $.command.register({ name: 'wb', description: 'Show or hide the PR / Jira / t band', immediate: true })
    // Listed from turn one, in front of ToolSearch, so the model reaches for it.
    await $.tool
      .register({
        name: 'set_topic',
        description: 'Show on the work band what you are working on now: one to three short labels. Call it when you start and whenever the topic changes.',
        inputSchema: {
          type: 'object',
          properties: { topics: { type: 'array', items: { type: 'string' }, minItems: 1, maxItems: TOPIC_MAX, description: 'Short labels, two to four words each' } },
          required: ['topics'],
        },
        isDeferred: false,
      })
      .catch(() => {})
    void checkRepo($)
    void refreshAccount($).catch(() => {})
    void $.process.run(['git', 'rev-parse', '--show-toplevel']).then(r => {
      if (r.exitCode === 0) repoTop = r.stdout.trim()
    })
    void refreshAll($)
    $.clock.every(POLL_MS, () => void refreshAll($))
    const stored = await $.store.get('port')
    if (typeof stored === 'number' && parsePort(String(stored)) !== undefined) await update($, port, () => stored)
    if ((await read($, serve)).state !== 'running') void pickFreePort($).catch(() => {})
    return started
  })

  on('turn.complete', async ($, e, next) => {
    const result = await next(e)
    if ((await $.clock.now()) - lastPrFetch > MIN_PR_GAP_MS) void refreshAll($)
    if (await isFilesOpen($)) void refreshFiles($).catch(() => {})
    return result
  })

  on('command.run', { command: 'wb' }, async $ => {
    const hidden = await update($, isHidden, h => !h)
    return { text: hidden ? 'Work band hidden. /wb shows it again.' : 'Work band shown.' }
  })

  // The model is told the band exists and how to set its topic, when the
  // tool is on offer.
  on('prompt.compose', async ($, e, next) => {
    const { sections } = await next(e)
    if (!e.tools.includes(TOPIC_TOOL)) return { sections }
    return { sections: [...sections, { id: 'work-band:topic', text: TOPIC_PROMPT, scope: 'session' }] }
  })

  // One hook, two jobs (the engine takes one matcher-less tool.call hook per
  // module, and the tool-name union is laid from this machine's connectors,
  // not from the mod's own tool, so neither can be a matcher):
  // the model names its topic through set_topic and the band draws it; the
  // file being edited spins in the Files pane, its folders opened.
  on('tool.call', async ($, e, next) => {
    if ((e.tool as string) === TOPIC_TOOL) {
      const topics = parseTopics(e)
      if (topics === undefined || topics.length === 0) return { deny: 'set_topic takes { topics: string[] }, one to three short labels' }
      await update($, topic, () => topics)
      // An MCP-named tool's result is checked against MCP's output shape: text.
      const text = `The band shows: ${topicText(topics)}`
      return { result: text, text }
    }
    if (!EDIT_TOOLS.has(e.tool)) return next(e)
    const input = e as unknown as { file_path?: string; notebook_path?: string }
    const file = input.file_path ?? input.notebook_path
    const path = file && repoTop ? relativeTo(repoTop, file) : undefined
    if (!path) return next(e)
    await startEdit($, path)
    try {
      return await next(e)
    } finally {
      $.clock.after(EDIT_LINGER_MS, () => void endEdit($, path).catch(() => {}))
    }
  })

  on('ui.render', { component: 'Pane', requestId: FILES_PANE }, async ($, e) => {
    const { Box, Button, Text } = $.ui.resolve(e)
    const [mode, opened, closed, frame] = await Promise.all([
      read($, filesMode),
      read($, openDirs),
      read($, closedDirs),
      read($, editFrame),
      read($, filesTick),
    ])
    const marks = marksOf(prChanges, uncommitted)
    const statuses = new Map([...prChanges, ...uncommitted].map(c => [c.path, c.status]))
    const editingPaths = [...editing.keys()]
    const shownPaths =
      mode === 'all'
        ? new Set([...allFiles, ...uncommitted.map(c => c.path), ...editingPaths])
        : new Set([...(mode === 'pr' ? prChanges : uncommitted).map(c => c.path), ...editingPaths])
    const forced = new Set(editingPaths.flatMap(ancestorsOf))
    const isOpen =
      mode === 'all'
        ? (dir: string) => forced.has(dir) || opened.includes(dir)
        : (dir: string) => forced.has(dir) || !closed.includes(dir)
    const rows = buildRows(shownPaths, isOpen, marks, statuses)
    const spin = SPINNER[frame % SPINNER.length]

    const modeButton = (key: FilesMode, label: string) => (
      <Button
        key={`mode-${key}`}
        label={label}
        variant={mode === key ? 'primary' : undefined}
        dimColor={mode !== key}
        onPress={() => update($, filesMode, () => key)}
      />
    )

    return (
      <Box flexDirection="column">
        <Box>
          {modeButton('all', `All ${allFiles.length}`)}
          <Text> </Text>
          {modeButton('pr', `PR ${prChanges.length}`)}
          <Text> </Text>
          {modeButton('uncommitted', `Uncommitted ${uncommitted.length}`)}
          <Text>   </Text>
          <Text color={MARK_COLOR.pr}>● in PR </Text>
          <Text color={MARK_COLOR.uncommitted}>● uncommitted</Text>
        </Box>
        {rows.length === 0 ? (
          <Text dimColor>{mode === 'pr' ? 'No changes against the PR base.' : 'Nothing uncommitted.'}</Text>
        ) : null}
        {rows.map(row => {
          const isEditing = editing.has(row.path)
          const indent = '  '.repeat(row.depth)
          const label = (
            <Text color={row.mark ? MARK_COLOR[row.mark] : undefined} bold={isEditing}>
              {row.isDir ? `${row.name}/` : row.name}
            </Text>
          )
          return row.isDir ? (
            <Button key={`dir:${row.path}`} plain label={row.path} onPress={() => toggleDir($, row.path)}>
              <Text dimColor>
                {indent}
                {row.isOpen ? '▾ ' : '▸ '}
              </Text>
              {label}
            </Button>
          ) : (
            <Text key={`file:${row.path}`} wrap="truncate-end">
              <Text dimColor>{indent}</Text>
              {isEditing ? <Text color="claude">{spin} </Text> : <Text>{'  '}</Text>}
              {label}
              {row.status ? <Text dimColor> {row.status}</Text> : null}
            </Text>
          )
        })}
      </Box>
    )
  })

  on('ui.render', { component: 'Pane', requestId: CHECKS_PANE }, async ($, e) => {
    const { Box, Button, Text } = $.ui.resolve(e)
    const [current, asked] = await Promise.all([read($, pr), read($, rerunAsked)])
    const now = await $.clock.now()
    const checks = current?.checks ?? []
    const all = rerunAll(checks).filter(argv => !asked.includes(argv[3]!))
    const broken = checks.filter(c => c.state === 'fail' || c.state === 'skipped').length

    return (
      <Box flexDirection="column">
        {current ? (
          <Text dimColor>
            {current.title}
          </Text>
        ) : (
          <Text dimColor>No PR for this branch.</Text>
        )}
        {current && checks.length === 0 ? <Text dimColor>No checks reported.</Text> : null}
        {all.length ? (
          <Box>
            <Button
              key="rerun-all"
              label={`Re-run failed and skipped (${broken})`}
              onPress={() => rerun($, all, `${broken} failed or skipped checks`)}
            />
          </Box>
        ) : null}
        {checks.map(c => {
          const took =
            c.startedAt && (c.completedAt || c.state === 'pending')
              ? formatDuration((c.completedAt ? Date.parse(c.completedAt) : now) - Date.parse(c.startedAt))
              : ''
          return (
            <Box key={`${c.workflow ?? ''}/${c.name}`}>
              <Text color={CHECK_COLOR[c.state]}>{CHECK_MARK[c.state]} </Text>
              <Text bold={c.state === 'fail'} dimColor={c.state === 'skipped'}>
                {c.name}
              </Text>
              {c.workflow ? <Text dimColor> · {c.workflow}</Text> : null}
              {took ? <Text dimColor> · {c.state === 'pending' ? `running ${took}` : took}</Text> : null}
              {c.url ? <Text> </Text> : null}
              {c.url ? (
                <Button key={`link-${c.workflow ?? ''}/${c.name}`} plain label="details" onPress={() => openUrl($, c.url!)}>
                  <Text>details</Text>
                </Button>
              ) : null}
              {(() => {
                const argv = rerunOne(c)
                if (!argv) return null
                if (asked.includes(argv[3]!)) return <Text dimColor> · re-run asked</Text>
                return [
                  <Text key={`rerun-sep-${c.workflow ?? ''}/${c.name}`}> </Text>,
                  <Button
                    key={`rerun:${c.workflow ?? ''}/${c.name}`}
                    label={c.state === 'fail' ? 'rerun' : 'run'}
                    onPress={() => rerun($, [argv], c.name)}
                  />,
                ]
              })()}
            </Box>
          )
        })}
      </Box>
    )
  })

  on('ui.render', { component: 'Pane', requestId: LOGS_PANE }, async ($, e) => {
    const { Box, Text } = $.ui.resolve(e)
    const { task } = await read($, logView)
    const lines = logs.get(task) ?? []
    const room = Math.max(1, e.props.scroll.bodyRows)

    return (
      <Box flexDirection="column">
        {lines.length === 0 ? <Text dimColor>No output from {task} yet.</Text> : null}
        {lines.slice(-room).map((line, i) => (
          <Text key={String(i)} wrap="truncate-end">
            {line || ' '}
          </Text>
        ))}
      </Box>
    )
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey || (await read($, isHidden))) return next(e)

    const [p, j, s, isServeRepo, at, d, acct, topics] = await Promise.all([
      read($, pr),
      read($, jira),
      read($, serve),
      read($, canServe),
      read($, port),
      read($, diffStat),
      read($, account),
      read($, topic),
    ])
    const topicLabel = topics.length ? topicText(topics) : undefined
    const { Box, Button, Text } = $.ui.resolve(e)

    // A Button cannot sit inside a Text, so the PR part is a list of the
    // row's own children; the check counts are the button.
    // `+455 −444`: the branch's diff against its PR's base (or develop);
    // clicking it opens the Files pane.
    const diffButton = (
      <Button key="files" plain label="Files" onPress={() => toggleFiles($)}>
        {d ? (
          <Text>
            <Text color="diffAdded">+{d.added}</Text> <Text color="diffRemoved">−{d.removed}</Text>
            {p ? '' : <Text dimColor> vs {d.base}</Text>}
          </Text>
        ) : (
          <Text dimColor>diff</Text>
        )}
      </Button>
    )
    const sep = (key: string) => (
      <Text key={key} dimColor>
        {' '}
        ·{' '}
      </Text>
    )
    const prPart = p
      ? [
          // The PR number opens the PR on GitHub.
          p.url ? (
            <Button key="pr" plain label={`PR #${p.number}`} onPress={() => openUrl($, p.url!)}>
              <Text bold>PR #{p.number}</Text>
            </Button>
          ) : (
            <Text key="pr" bold>
              PR #{p.number}
            </Text>
          ),
          <Text key="pr-state" color={p.state === 'merged' ? 'merged' : p.state === 'closed' ? 'error' : undefined}>
            {' '}
            {p.isDraft ? 'draft' : p.state}
          </Text>,
          sep('sep-diff'),
          diffButton,
          sep('sep-checks'),
          <Button key="checks" plain label="CI checks" onPress={() => toggleChecks($)}>
            <Text color="success">✓{p.passed}</Text>{' '}
            <Text color={p.failed ? 'error' : 'subtle'}>✗{p.failed}</Text>{' '}
            <Text color={p.pending ? 'warning' : 'subtle'}>…{p.pending}</Text>
          </Button>,
        ]
      : [
          <Text key="no-pr" dimColor>
            no PR
          </Text>,
          sep('sep-diff'),
          diffButton,
        ]

    // The key opens the issue in the browser; a Button is a row child, not
    // inside a Text.
    const jiraPart = j ? (
      [
        <Button key="jira" plain label={j.key} onPress={() => openUrl($, jiraUrl(j.key))}>
          <Text bold>{j.key}</Text>
        </Button>,
        'title' in j ? (
          [
            j.status ? (
              <Button key="jira-state" plain label={`Change ${j.key} status`} onPress={() => changeJiraStatus($)}>
                <Text>
                  {' '}
                  {j.status}
                </Text>
              </Button>
            ) : null,
            <Text key="jira-title" dimColor wrap="truncate-end">
              {' '}
              {j.title}
            </Text>,
          ]
        ) : (
          <Text key="jira-status" dimColor>
            {' '}
            {j.error}
          </Text>
        ),
      ]
    ) : (
      <Text dimColor>no Jira key</Text>
    )

    const exitedLabel =
      s.state === 'exited' ? `exited${s.code != null ? ` ${s.code}` : s.signal ? ` (${s.signal})` : ''}` : null

    // Too wide for one row: the Jira issue takes a row of its own, its title cut
    // to the band, so the band is three rows rather than a wrapped one.
    const serveText = isServeRepo ? `   [ server :${at} ^ ]${exitedLabel ? ` ${exitedLabel}` : ''}` : ''
    const jiraOnOwnRow =
      j !== null && 'title' in j && firstRowWidth({ pr: p, diff: d, jira: j, serve: serveText, plan: acct?.plan, topic: topicLabel }) > e.props.bodyColumns
    const jiraRow =
      jiraOnOwnRow && j && 'title' in j ? (
        <Box>
          <Button key="jira" plain label={j.key} onPress={() => openUrl($, jiraUrl(j.key))}>
            <Text bold>{j.key}</Text>
          </Button>
          {j.status ? (
            <Button key="jira-state" plain label={`Change ${j.key} status`} onPress={() => changeJiraStatus($)}>
              <Text>
                {' '}
                {j.status}
              </Text>
            </Button>
          ) : null}
          <Text key="jira-title" dimColor wrap="truncate-end">
            {' '}
            {fitWidth(j.title, e.props.bodyColumns - j.key.length - 1 - (j.status ? j.status.length + 1 : 0))}
          </Text>
        </Box>
      ) : null

    return (
      <Box flexDirection="column">
        <Box>
          {prPart}
          {jiraOnOwnRow ? null : <Text dimColor>   </Text>}
          {jiraOnOwnRow ? null : jiraPart}
          {topicLabel ? (
            <Text key="topic" color="cyan" wrap="truncate-end">
              {'   '}
              {topicLabel}
            </Text>
          ) : null}
          {isServeRepo ? (
            // `[ server ^ ]`: two chrome-less buttons inside drawn brackets,
            // since one Button is one press target.
            <Text>   [ </Text>
          ) : null}
          {isServeRepo ? (
            <Button key="serve" plain label="server" onPress={() => restartServe($)}>
              <Text color={s.state === 'running' ? 'success' : undefined}>server</Text>
            </Button>
          ) : null}
          {isServeRepo ? <Text> </Text> : null}
          {isServeRepo ? (
            <Button key="port" plain label={`Open ${serverUrl(at)}`} onPress={() => openServer($)}>
              <Text dimColor>:{at}</Text>
            </Button>
          ) : null}
          {isServeRepo ? <Text> </Text> : null}
          {isServeRepo ? <Button key="menu" plain label="^" onPress={() => openServeMenu($)} /> : null}
          {isServeRepo ? <Text> ]</Text> : null}
          {exitedLabel && isServeRepo ? <Text color="error"> {exitedLabel}</Text> : null}
          {acct ? (
            <Text>
              {'   '}
              <Text color="magenta">{acct.plan}</Text>
            </Text>
          ) : null}
        </Box>
        {jiraRow}
        {isServeRepo && tasksOf(s).length ? (
          <Box>
            {tasksOf(s).flatMap((t, i) => [
              ...(i ? [<Text key={`sep-${t.name}`} dimColor> · </Text>] : []),
              <Button key={`task-${t.name}`} plain label={`${t.name} logs`} onPress={() => toggleLogs($, t.name)}>
                <Text
                  color={TASK_COLOR[t.state]}
                  bold={t.state === 'running' && t.flash}
                  dimColor={t.state === 'pending' || t.state === 'stopped' || (t.state === 'running' && !t.flash)}
                >
                  {TASK_MARK[t.state]} {t.name}
                  {t.state === 'failed' && t.code != null ? ` (${t.code})` : ''}
                </Text>
              </Button>,
            ])}
          </Box>
        ) : null}
      </Box>
    )
  })
}
