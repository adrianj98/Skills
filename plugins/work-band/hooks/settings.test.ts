import { expect, test } from 'claude-code/testing'

import {
  describe,
  detectServers,
  issueKey,
  jiraSite,
  parseEnv,
  parsePorts,
  parseSettingsFile,
  planArgv,
  ports,
  repoOf,
  serverArgv,
  serverEnv,
  serverKind,
  serverMatch,
} from './settings'

const ALERTD = {
  jira: { site: 'alertd.atlassian.net' },
  server: { kind: 'turbo' as const, portEnv: 'WEB_PORT', ports: [1776, 1791, 1792], env: { ORCHESTRATOR_SINGLETON_GATE: 'false' } },
}

test('the repo is owner/repo of a GitHub remote, ssh or https; nothing for another host', () => {
  expect(repoOf('git@github.com:alert-d/alertd-core.git\n')).toBe('alert-d/alertd-core')
  expect(repoOf('https://github.com/adrianj98/Skills')).toBe('adrianj98/Skills')
  expect(repoOf('https://github.com/o/r.git/')).toBe('o/r')
  expect(repoOf('git@gitlab.com:o/r.git')).toBe(undefined)
})

test('a settings file that is not an object reads as no settings', () => {
  expect(parseSettingsFile('{"o/r":{"enabled":false}}')).toEqual({ 'o/r': { enabled: false } })
  expect(parseSettingsFile('[1]')).toEqual({})
  expect(parseSettingsFile('nope')).toEqual({})
})

test('Jira is on only with a site', () => {
  expect(jiraSite({})).toBe(undefined)
  expect(jiraSite({ jira: { site: '  ' } })).toBe(undefined)
  expect(jiraSite(ALERTD)).toBe('alertd.atlassian.net')
})

test('the issue key: the PR title first, then the branch, from the allowed projects', () => {
  expect(issueKey({}, 'feat: AL-12 x', 'OPS-3-y')).toBe('AL-12')
  expect(issueKey({}, 'no key', 'OPS-3-y')).toBe('OPS-3')
  expect(issueKey({ jira: { projects: ['OPS'] } }, 'feat: AL-12 x', 'OPS-3-y')).toBe('OPS-3')
  expect(issueKey({ jira: { keyPattern: 'TK\\d+' } }, 'fix TK42', '')).toBe('TK42')
  expect(issueKey({}, 'nothing', 'main')).toBe(undefined)
})

test('no server unless one is set; turbo has a plan, plain does not', () => {
  expect(serverKind({})).toBe('none')
  expect(serverArgv({})).toEqual([])
  expect(serverKind({ server: { kind: 'plain' } })).toBe('none')
  expect(serverArgv(ALERTD)).toEqual(['npx', 'turbo', 'run', 'serve', '--ui=stream'])
  expect(planArgv(ALERTD)).toEqual(['npx', 'turbo', 'run', 'serve', '--dry=json'])
  const plain = { server: { kind: 'plain' as const, command: ['npm', 'run', 'dev'] } }
  expect(serverArgv(plain)).toEqual(['npm', 'run', 'dev'])
  expect(planArgv(plain)).toBe(undefined)
  expect(serverMatch(ALERTD)).toBe('turbo run serve')
  expect(serverMatch(plain)).toBe('run dev')
})

test('the server env: extra env, then the port under its variable', () => {
  expect(serverEnv(ALERTD, 1791)).toEqual({ FORCE_COLOR: '0', ORCHESTRATOR_SINGLETON_GATE: 'false', WEB_PORT: '1791' })
  expect(serverEnv({ server: { kind: 'plain', command: ['x'] } }, 3000)).toEqual({ FORCE_COLOR: '0', PORT: '3000' })
  expect(ports({})).toEqual([3000])
  expect(ports({ server: { ports: [0, 5173, 70000] } })).toEqual([5173])
})

test('servers are offered from turbo.json and package.json', () => {
  expect(detectServers('{"tasks":{"//#serve":{},"//#build":{}}}', '{"scripts":{"dev":"vite","test":"x"}}')).toEqual([
    { label: 'turbo run serve', kind: 'turbo', command: ['npx', 'turbo', 'run', 'serve', '--ui=stream'] },
    { label: 'npm run dev', kind: 'plain', command: ['npm', 'run', 'dev'] },
  ])
  expect(detectServers(undefined, undefined)).toEqual([])
  expect(detectServers('not json', '{"scripts":{"start":"node ."}}')).toEqual([{ label: 'npm run start', kind: 'plain', command: ['npm', 'run', 'start'] }])
})

test('ports and env are read from what the person types', () => {
  expect(parsePorts('1776, 1791 1792')).toEqual([1776, 1791, 1792])
  expect(parsePorts('80, x')).toBe(undefined)
  expect(parsePorts('')).toBe(undefined)
  expect(parseEnv('A=1 B=two=2')).toEqual({ A: '1', B: 'two=2' })
  expect(parseEnv('A=1 nope')).toBe(undefined)
})

test('the settings pane lists the server rows only when there is a server', () => {
  expect(describe({}).map(r => r.label)).toEqual(['Band', 'Jira site', 'Jira projects', 'Server'])
  expect(describe(ALERTD).map(r => `${r.label}: ${r.value}`)).toEqual([
    'Band: on',
    'Jira site: alertd.atlassian.net',
    'Jira projects: any',
    'Server: turbo: npx turbo run serve --ui=stream',
    'Port variable: WEB_PORT',
    'Ports: 1776, 1791, 1792',
    'Extra env: ORCHESTRATOR_SINGLETON_GATE=false',
  ])
})
