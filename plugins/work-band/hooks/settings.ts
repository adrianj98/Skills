// The band's per-repo settings, kept in one file in the person's home folder
// (`~/.claude/work-band.json`), keyed by `owner/repo`; nothing is stored in
// the repo. A repo with no entry gets the defaults: the band on, no Jira, no
// server.

import type { RepoSettings, ServerKind } from '../types'

export const SETTINGS_FILE = 'work-band.json'

// `git@github.com:alert-d/alertd-core.git`, `https://github.com/o/r` → `o/r`;
// undefined for a remote that is not on GitHub.
export const repoOf = (remote: string): string | undefined =>
  /github\.com[:/]([^/\s]+\/[^/\s]+?)(?:\.git)?\/?$/.exec(remote.trim())?.[1]

// The whole file, one entry per repo; anything that is not an object reads
// as no settings.
export const parseSettingsFile = (text: string): Record<string, RepoSettings> => {
  try {
    const all = JSON.parse(text) as unknown
    return all && typeof all === 'object' && !Array.isArray(all) ? (all as Record<string, RepoSettings>) : {}
  } catch {
    return {}
  }
}

export const formatSettingsFile = (all: Record<string, RepoSettings>): string => `${JSON.stringify(all, null, 2)}\n`

export const isEnabled = (s: RepoSettings): boolean => s.enabled !== false

// Jira runs only where its site is set.
export const jiraSite = (s: RepoSettings): string | undefined => s.jira?.site?.trim() || undefined

export const DEFAULT_KEY_PATTERN = '[A-Z][A-Z0-9]+-\\d+'
export const keyPattern = (s: RepoSettings): RegExp => {
  try {
    return new RegExp(`\\b(?:${s.jira?.keyPattern || DEFAULT_KEY_PATTERN})\\b`)
  } catch {
    return new RegExp(`\\b(?:${DEFAULT_KEY_PATTERN})\\b`)
  }
}

// The issue key in the PR title, else the branch, from an allowed project.
export const issueKey = (s: RepoSettings, ...texts: readonly string[]): string | undefined => {
  const pattern = keyPattern(s)
  const projects = s.jira?.projects?.length ? s.jira.projects : undefined
  for (const text of texts) {
    const key = text.match(pattern)?.[0]
    if (key && (!projects || projects.includes(key.split('-')[0]!))) return key
  }
  return undefined
}

export const TURBO_SERVE = ['npx', 'turbo', 'run', 'serve', '--ui=stream']

export const serverKind = (s: RepoSettings): ServerKind => {
  const k = s.server?.kind
  if (k === 'turbo' || k === 'plain') return s.server?.command?.length || k === 'turbo' ? k : 'none'
  return 'none'
}

// What starts the server; empty when there is none.
export const serverArgv = (s: RepoSettings): readonly string[] => {
  const kind = serverKind(s)
  if (kind === 'none') return []
  return s.server?.command?.length ? s.server.command : TURBO_SERVE
}

// Turbo's plan of the tasks the server runs: the same command, dry.
export const planArgv = (s: RepoSettings): readonly string[] | undefined => {
  if (serverKind(s) !== 'turbo') return undefined
  const argv = serverArgv(s).filter(a => !a.startsWith('--ui'))
  return [...argv, '--dry=json']
}

export const portEnv = (s: RepoSettings): string => s.server?.portEnv?.trim() || 'PORT'
// `server.ports`: one list of single ports and ranges, tried in its order,
// e.g. `[1988, 3000, "1943-1960"]` (typed as `1988, 3000, 1943-1960`). A range
// stands for any free port in it, taken at random; random ports come from
// nowhere else. An old `server.portRange` reads as a range at the front.
export type PortRange = { from: number; to: number }
export type PortEntry = number | PortRange
export const parsePortRange = (text: string): PortRange | undefined => {
  const m = /^\s*(\d+)\s*[-–]\s*(\d+)\s*$/.exec(text)
  if (!m) return undefined
  const from = Number(m[1])
  const to = Number(m[2])
  return from >= 1 && to <= 65535 && from <= to ? { from, to } : undefined
}
const isPort = (n: number) => Number.isInteger(n) && n > 0 && n < 65536
const entryOf = (raw: unknown): PortEntry | undefined => {
  if (typeof raw === 'number') return isPort(raw) ? raw : undefined
  if (typeof raw !== 'string') return undefined
  return /^\s*\d+\s*$/.test(raw) && isPort(Number(raw)) ? Number(raw) : parsePortRange(raw)
}
export const portEntries = (s: RepoSettings): readonly PortEntry[] => {
  const raw = s.server?.ports
  const items: unknown[] = typeof raw === 'string' ? raw.split(/[\s,]+/).filter(Boolean) : Array.isArray(raw) ? raw : []
  const list = [...(s.server?.portRange ? [s.server.portRange] : []), ...items]
    .map(entryOf)
    .filter((e): e is PortEntry => e !== undefined)
  return list.length ? list : [3000]
}
// The single ports in the list, for the Change port menu.
export const ports = (s: RepoSettings): readonly number[] => portEntries(s).filter((e): e is number => typeof e === 'number')
// The port a session starts on: the first entry when it is a single port;
// undefined when it is a range (a random free one from it).
export const firstPort = (s: RepoSettings): number | undefined => {
  const first = portEntries(s)[0]
  return typeof first === 'number' ? first : undefined
}
const entryText = (e: PortEntry) => (typeof e === 'number' ? String(e) : `${e.from}-${e.to}`)
export const formatPorts = (list: readonly PortEntry[]): string => list.map(entryText).join(', ')

// What a process of this server's command looks like in `ps`, to find one
// this session started and lost track of.
export const serverMatch = (s: RepoSettings): string => serverArgv(s).filter(a => !a.startsWith('-')).slice(1).join(' ')

export const serverEnv = (s: RepoSettings, at: number): Record<string, string> => ({
  FORCE_COLOR: '0',
  ...(s.server?.env ?? {}),
  [portEnv(s)]: String(at),
})

// A server the repo looks like it has, offered by the wizard, never started
// unasked.
export type ServerChoice = { label: string; kind: ServerKind; command: string[] }
export const detectServers = (turboJson: string | undefined, packageJson: string | undefined): ServerChoice[] => {
  const out: ServerChoice[] = []
  try {
    const tasks = Object.keys((JSON.parse(turboJson ?? '') as { tasks?: object; pipeline?: object }).tasks ?? {})
    if (tasks.some(t => t === 'serve' || t.endsWith('#serve'))) out.push({ label: 'turbo run serve', kind: 'turbo', command: TURBO_SERVE })
  } catch {
    // no turbo.json, or not JSON
  }
  try {
    const scripts = (JSON.parse(packageJson ?? '') as { scripts?: Record<string, string> }).scripts ?? {}
    for (const name of ['dev', 'serve', 'start']) {
      if (scripts[name]) out.push({ label: `npm run ${name}`, kind: 'plain', command: ['npm', 'run', name] })
    }
  } catch {
    // no package.json, or not JSON
  }
  return out
}

// `1988, 3000 1943-1960` → [1988, 3000, '1943-1960'], as `server.ports` keeps
// it; undefined when any part is neither a port nor a range.
export const parsePorts = (text: string): (number | string)[] | undefined => {
  const entries = text.split(/[\s,]+/).filter(Boolean).map(entryOf)
  if (!entries.length || entries.some(e => e === undefined)) return undefined
  return (entries as PortEntry[]).map(e => (typeof e === 'number' ? e : entryText(e)))
}

// `A=1 B=two` → { A: '1', B: 'two' }; undefined when a part has no `=`.
export const parseEnv = (text: string): Record<string, string> | undefined => {
  const parts = text.split(/\s+/).filter(Boolean)
  if (!parts.every(p => /^[A-Za-z_][A-Za-z0-9_]*=/.test(p))) return undefined
  return Object.fromEntries(parts.map(p => [p.slice(0, p.indexOf('=')), p.slice(p.indexOf('=') + 1)]))
}

// One line per setting, as the settings pane lists them.
export const describe = (s: RepoSettings): { key: string; label: string; value: string }[] => {
  const kind = serverKind(s)
  return [
    { key: 'enabled', label: 'Band', value: isEnabled(s) ? 'on' : 'off' },
    { key: 'jira.site', label: 'Jira site', value: jiraSite(s) ?? 'none (Jira off)' },
    { key: 'jira.projects', label: 'Jira projects', value: s.jira?.projects?.join(', ') || 'any' },
    { key: 'server.kind', label: 'Server', value: kind === 'none' ? 'none' : `${kind}: ${serverArgv(s).join(' ')}` },
    ...(kind === 'none'
      ? []
      : [
          { key: 'server.portEnv', label: 'Port variable', value: portEnv(s) },
          { key: 'server.ports', label: 'Ports', value: formatPorts(portEntries(s)) },
          { key: 'server.env', label: 'Extra env', value: Object.entries(s.server?.env ?? {}).map(([k, v]) => `${k}=${v}`).join(' ') || 'none' },
        ]),
  ]
}
