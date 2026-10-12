// The Files pane's tree: pure functions over repo-relative paths.

export type Mark = 'uncommitted' | 'pr'

export type Change = { path: string; status: string }

export type Row = {
  path: string
  name: string
  depth: number
  isDir: boolean
  isOpen: boolean
  mark?: Mark
  status?: string
}

// `git status --porcelain=v1 -uall`: `XY path`, or `XY old -> new` for a rename.
export const parseStatus = (porcelain: string): Change[] =>
  porcelain
    .split('\n')
    .filter(line => line.length > 3)
    .map(line => ({
      status: line.slice(0, 2).trim() || '?',
      path: line.slice(3).split(' -> ').pop()!.replace(/^"|"$/g, ''),
    }))

// `git diff --name-status base...HEAD`: `M\tpath`, or `R100\told\tnew`.
export const parseNameStatus = (diff: string): Change[] =>
  diff
    .split('\n')
    .filter(Boolean)
    .map(line => {
      const [status = '', ...paths] = line.split('\t')
      return { status: status.charAt(0), path: paths[paths.length - 1] ?? '' }
    })
    .filter(c => c.path)

// Every folder above a path: `a/b/c.ts` → `a`, `a/b`.
export const ancestorsOf = (path: string): string[] => {
  const parts = path.split('/').slice(0, -1)
  return parts.map((_, i) => parts.slice(0, i + 1).join('/'))
}

type Dir = { dirs: Map<string, Dir>; files: Set<string> }

const newDir = (): Dir => ({ dirs: new Map(), files: new Set() })

const treeOf = (paths: Iterable<string>): Dir => {
  const root = newDir()
  for (const path of paths) {
    const parts = path.split('/')
    let dir = root
    for (const part of parts.slice(0, -1)) {
      let next = dir.dirs.get(part)
      if (!next) dir.dirs.set(part, (next = newDir()))
      dir = next
    }
    dir.files.add(parts[parts.length - 1]!)
  }
  return root
}

// The mark a folder shows: uncommitted if any file under it is, else pr.
export const folderMarks = (marks: ReadonlyMap<string, Mark>): Map<string, Mark> => {
  const out = new Map<string, Mark>()
  for (const [path, mark] of marks) {
    for (const dir of ancestorsOf(path)) {
      if (out.get(dir) !== 'uncommitted') out.set(dir, mark)
    }
  }
  return out
}

// The rows a pane shows, folders first then files, each level by name.
// `isOpen(dir)` says which folders are expanded.
export const buildRows = (
  paths: Iterable<string>,
  isOpen: (dir: string) => boolean,
  marks: ReadonlyMap<string, Mark>,
  statuses: ReadonlyMap<string, string>,
): Row[] => {
  const dirMarks = folderMarks(marks)
  const rows: Row[] = []
  const walk = (dir: Dir, prefix: string, depth: number) => {
    for (const name of [...dir.dirs.keys()].sort()) {
      const path = prefix + name
      const open = isOpen(path)
      rows.push({ path, name, depth, isDir: true, isOpen: open, mark: dirMarks.get(path) })
      if (open) walk(dir.dirs.get(name)!, `${path}/`, depth + 1)
    }
    for (const name of [...dir.files].sort()) {
      const path = prefix + name
      rows.push({ path, name, depth, isDir: false, isOpen: false, mark: marks.get(path), status: statuses.get(path) })
    }
  }
  walk(treeOf(paths), '', 0)
  return rows
}

// Each file's mark: uncommitted wins over pr when a file is both.
export const marksOf = (pr: readonly Change[], uncommitted: readonly Change[]): Map<string, Mark> => {
  const marks = new Map<string, Mark>()
  for (const c of pr) marks.set(c.path, 'pr')
  for (const c of uncommitted) marks.set(c.path, 'uncommitted')
  return marks
}

// `/repo/src/a.ts` under `/repo` → `src/a.ts`; a path outside → undefined.
export const relativeTo = (top: string, file: string): string | undefined => {
  const root = top.endsWith('/') ? top : `${top}/`
  return file.startsWith(root) ? file.slice(root.length) : undefined
}
