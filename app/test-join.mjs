// Tests the data join (app/join.js) with sample `herdr agent list` JSON and feed files. Run by scripts/test-app.sh.
import { readFileSync, readdirSync } from 'node:fs'
import assert from 'node:assert/strict'

const dir = new URL('./demo/', import.meta.url)
const src = readFileSync(new URL('./join.js', import.meta.url), 'utf8').replace(/^\.pragma library\n/, '')
const { buildModel } = new Function(`${src}; return { buildModel }`)()

const agents = JSON.parse(readFileSync(new URL('agents.json', dir), 'utf8')).result.agents
const feed = {}
for (const f of readdirSync(dir)) if (f.startsWith('feed-')) feed[f.slice(5, -5)] = JSON.parse(readFileSync(new URL(f, dir), 'utf8'))
const NOW = 1000 + 12 * 60 + 5
const m = buildModel({ host: 'workstation', now: NOW, agents, feed })
const rows = m.rows
const sessions = rows.filter(r => r.kind === 'session')
const by = key => sessions.find(r => r.key === key)
let n = 0
const t = (name, fn) => { fn(); n++; console.log(`ok   ${name}`) }

t('one machine row, with the host name', () => {
  assert.equal(rows[0].kind, 'machine'); assert.equal(rows[0].title, 'workstation'); assert.equal(rows[0].count, '5')
})
t('every agent becomes one card', () => assert.equal(sessions.length, 5))
t('cards group by project', () => {
  const projects = rows.filter(r => r.kind === 'project')
  assert.deepEqual(projects.map(p => `${p.title}:${p.count}`), ['canvas-app:2', 'dotfiles:1', 'acme-site:2'])
})
t('the project with a card that needs you comes first, and the card too', () => {
  assert.equal(rows[1].title, 'canvas-app'); assert.equal(rows[2].key, 's:w1:p2')
})
t('herdr status maps to state: blocked -> needs, idle -> ready', () => {
  assert.equal(by('s:w1:p2').state, 'needs')
  const idle = buildModel({ host: 'h', now: NOW, agents: [{ ...agents[3], agent_status: 'idle' }], feed: {} }).rows[2]
  assert.equal(idle.state, 'ready')
})
t('the feed adds "failed" on an idle agent', () => assert.equal(by('s:w2:p2').state, 'failed'))
t('a working agent stays working', () => assert.equal(by('s:w1:p3').state, 'working'))
t('the feed gives title, type label, branch, context and time', () => {
  const c = by('s:w1:p1')
  assert.equal(c.title, 'Fix Vercel POST hang'); assert.equal(c.kindLabel, 'Agent · Opus')
  assert.equal(c.facts, 'fix/post-hang · 62 % · 12m'); assert.equal(c.context, 62); assert.equal(c.last, 'The form works again')
})
t('a card that needs you shows the question as its last line', () => assert.equal(by('s:w1:p2').last, 'Allow Bash: git push origin release/0.4?'))
t('the plan items are passed on', () => {
  const c = by('s:w1:p3'); assert.equal(c.planDone, 2); assert.equal(c.planTotal, 4); assert.equal(JSON.parse(c.planItems).length, 3)
})
t('with no feed file: the name or the terminal title, the folder as project, no bar', () => {
  const a = by('s:w2:p1'), b = by('s:w2:p2')
  assert.equal(a.title, 'acme-site'); assert.equal(a.project, 'acme-site'); assert.equal(a.context, -1); assert.equal(a.hasFeed, false)
  assert.equal(by('s:w1:p2').hasFeed, true); assert.equal(b.hasFeed, true)
  const named = buildModel({ host: 'h', now: NOW, agents: [agents[2]], feed: {} }).rows[2]
  assert.equal(named.title, 'dark-mode'); assert.equal(named.target, 'dark-mode')
})
t('the target is the name, or the pane id when there is no name', () => {
  assert.equal(by('s:w1:p1').target, 'post-hang'); assert.equal(by('s:w1:p2').target, 'w1:p2')
})
t('the "N need you" count', () => assert.equal(m.needCount, 1))
t('the weekly limit comes from the freshest feed file', () => {
  assert.equal(m.weekly.pct, 41); assert.match(m.weekly.resets, /^resets (Sunday|Monday|Tuesday|Wednesday|Thursday|Friday|Saturday)$/)
})
t('no weekly field in any file: no card', () => assert.equal(buildModel({ host: 'h', agents, feed: {} }).weekly.pct, -1))
t('an empty agent list gives only the machine row', () => {
  const e = buildModel({ host: 'h', agents: [], feed: {} }); assert.equal(e.rows.length, 1); assert.equal(e.needCount, 0)
})
t('a feed file with wrong types does not crash', () => {
  const bad = buildModel({ host: 'h', now: NOW, agents: [agents[0]], feed: { w1_p1: { state: 5, title: 7, plan: 'x', context: 'a' } } })
  assert.equal(bad.rows.filter(r => r.kind === 'session').length, 1)
})
console.log(`${n} data-join checks passed`)
