import { expect, test } from 'claude-code/testing'

import { ancestorsOf, buildRows, folderMarks, marksOf, parseNameStatus, parseStatus, relativeTo } from './tree'

test('git status: modified, untracked, staged rename', () => {
  expect(parseStatus(' M src/a.ts\n?? AGENTS.md\nR  old/b.ts -> new/b.ts\n')).toEqual([
    { status: 'M', path: 'src/a.ts' },
    { status: '??', path: 'AGENTS.md' },
    { status: 'R', path: 'new/b.ts' },
  ])
})

test('git diff --name-status: modified, added, renamed with score', () => {
  expect(parseNameStatus('M\tsrc/a.ts\nA\tsrc/b.ts\nR100\tsrc/old.ts\tsrc/new.ts\n')).toEqual([
    { status: 'M', path: 'src/a.ts' },
    { status: 'A', path: 'src/b.ts' },
    { status: 'R', path: 'src/new.ts' },
  ])
})

test('folders above a path', () => {
  expect(ancestorsOf('src/utils/mateoas/apiPage.ts')).toEqual(['src', 'src/utils', 'src/utils/mateoas'])
  expect(ancestorsOf('README.md')).toEqual([])
})

test('uncommitted wins over pr, for a file and for the folders above it', () => {
  const marks = marksOf(
    [
      { path: 'src/a.ts', status: 'M' },
      { path: 'src/b.ts', status: 'M' },
      { path: 'docs/c.md', status: 'A' },
    ],
    [{ path: 'src/b.ts', status: 'M' }],
  )
  expect([...marks]).toEqual([
    ['src/a.ts', 'pr'],
    ['src/b.ts', 'uncommitted'],
    ['docs/c.md', 'pr'],
  ])
  expect(folderMarks(marks)).toEqual(
    new Map([
      ['src', 'uncommitted'],
      ['docs', 'pr'],
    ]),
  )
})

test('rows: folders first, by name; a closed folder hides what is under it', () => {
  const paths = ['src/b.ts', 'src/a/x.ts', 'README.md', 'docs/y.md']
  const rows = buildRows(paths, dir => dir === 'src', new Map([['src/a/x.ts', 'pr']]), new Map([['src/a/x.ts', 'M']]))
  expect(rows.map(r => [r.depth, r.isDir ? `${r.name}/` : r.name, r.isOpen, r.mark ?? null])).toEqual([
    [0, 'docs/', false, null],
    [0, 'src/', true, 'pr'],
    [1, 'a/', false, 'pr'],
    [1, 'b.ts', false, null],
    [0, 'README.md', false, null],
  ])
})

test('an edited path is made relative to the repo; one outside it is not', () => {
  expect(relativeTo('/repo', '/repo/src/a.ts')).toBe('src/a.ts')
  expect(relativeTo('/repo/', '/repo/src/a.ts')).toBe('src/a.ts')
  expect(relativeTo('/repo', '/repository/a.ts')).toBe(undefined)
  expect(relativeTo('/repo', '/tmp/a.ts')).toBe(undefined)
})
