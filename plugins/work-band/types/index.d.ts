export type CheckState = 'pass' | 'fail' | 'pending' | 'skipped'
export type Check = {
  name: string
  workflow?: string
  state: CheckState
  startedAt?: string
  completedAt?: string
  url?: string
}
export type Pr = {
  number: number
  state: string
  isDraft: boolean
  passed: number
  failed: number
  pending: number
  title: string
  checks?: Check[]
  base?: string
  url?: string
}
export type Account = { plan: string; org?: string; email?: string }
export type DiffStat = { added: number; removed: number; base: string }
export type FilesMode = 'all' | 'pr' | 'uncommitted'
// `status` is the issue's status abbreviated (To Do → TODO), absent when Jira gave none.
export type Jira = { key: string; title: string; status?: string } | { key: string; error: string }
export type Task = {
  name: string
  state: 'pending' | 'running' | 'done' | 'failed' | 'stopped'
  code?: number
  persistent: boolean
  deps: string[]
  // lit while the task prints
  flash?: boolean
}
export type Serve = {
  state: 'stopped' | 'running' | 'exited'
  code?: number | null
  signal?: string
  tasks: readonly Task[]
}

declare module 'claude-code' {
  interface PluginState {
    'work-band': { pr: Pr | null; jira: Jira | null; serve: Serve; canServe: boolean; isHidden: boolean; logView: { task: string; tick: number }; mergedTold: number[]
      port: number
      filesMode: FilesMode
      openDirs: string[]
      closedDirs: string[]
      filesTick: number
      editFrame: number
      diffStat: DiffStat | null
      rerunAsked: string[]
      account: Account | null
    }
  }
}
