.pragma library
// The data join of the Graphite app: `herdr agent list` + the H2 feed files -> machines -> projects -> sessions.
// Pure functions with no I/O, so scripts/test-app.sh runs them in node with sample JSON.
// `.pragma library` is a Qt directive: the test removes the first line.

var RANK = { needs: 0, failed: 1, working: 2, ready: 3, done: 4 }
var DAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday']

function base(path) {
  var p = String(path || '').split('/').filter(function (s) { return s !== '' })
  return p.length ? p[p.length - 1] : ''
}

// herdr's live status wins for the exact moment of a change. The feed adds "failed".
function stateOf(status, feed) {
  var live = { blocked: 'needs', working: 'working', done: 'done', idle: 'ready' }[status] || 'ready'
  if (feed && feed.state === 'failed' && live !== 'working') return 'failed'
  return live
}

function ago(seconds) {
  var m = Math.floor(Math.max(0, seconds) / 60)
  if (m < 1) return 'now'
  if (m < 60) return m + 'm'
  var h = Math.floor(m / 60)
  return h < 24 ? h + 'h' : Math.floor(h / 24) + 'd'
}

function stText(state, feed, now) {
  if (state === 'needs') return 'needs you'
  if (state === 'working') return 'working'
  if (state === 'failed') return 'failed'
  return state === 'done' ? 'done' : 'ready'
}

function modelWord(model) { return String(model || '').split(' ')[0] }

function card(agent, feed, host, now) {
  var f = feed || null
  var state = stateOf(agent.agent_status, f)
  var title = (f && f.title) || agent.name || agent.terminal_title_stripped || base(agent.cwd) || agent.pane_id
  var kind = 'Agent · ' + ((f && modelWord(f.model)) || agent.agent || 'agent')
  var started = f && f.started ? f.started : 0
  var parts = []
  if (f && f.branch) parts.push(f.branch)
  if (f && f.context !== null && f.context !== undefined) parts.push(Math.round(f.context) + ' %')
  if (started) parts.push(ago(now - started))
  var plan = f && f.plan ? f.plan : { done: 0, total: 0, items: [] }
  return {
    key: 's:' + agent.pane_id,
    kind: 'session',
    machine: (f && f.machine) || host,
    project: (f && f.project) || base(agent.cwd) || 'no project',
    target: agent.name || agent.pane_id,
    pane: agent.pane_id,
    title: title,
    state: state,
    stText: stText(state, f, now),
    kindLabel: kind,
    branch: (f && f.branch) || '',
    facts: parts.join(' · '),
    context: f && f.context !== null && f.context !== undefined ? Math.round(f.context) : -1,
    last: (f && (state === 'needs' && f.ask ? f.ask : f.last)) || '',
    activity: (f && f.activity) || '',
    planDone: plan.done || 0,
    planTotal: plan.total || 0,
    planItems: JSON.stringify(plan.items || []),
    hasFeed: !!f
  }
}

// The weekly limit: from the freshest feed file that has it.
function weekly(feeds) {
  var best = null
  Object.keys(feeds || {}).forEach(function (k) {
    var f = feeds[k]
    if (f && typeof f.weekly === 'number' && (!best || (f.updated || 0) > (best.updated || 0))) best = f
  })
  if (!best) return { pct: -1, resets: '' }
  var r = best.weekly_reset ? 'resets ' + DAYS[new Date(best.weekly_reset * 1000).getDay()] : ''
  return { pct: Math.round(best.weekly), resets: r }
}

// input: { host, now (epoch s), agents: [agent list entries], feed: { <sanitized pane id>: feed json } }
// output: { host, needCount, total, weekly, rows: [flat rows: machine, project, session] }
function buildModel(input) {
  var host = input.host || 'this machine'
  var now = input.now || Math.floor(Date.now() / 1000)
  var feeds = input.feed || {}
  var cards = (input.agents || []).map(function (a) {
    var f = feeds[String(a.pane_id).replace(/[^A-Za-z0-9._-]/g, '_')]
    return card(a, f, host, now)
  })
  var projects = {}
  cards.forEach(function (c) {
    (projects[c.project] = projects[c.project] || []).push(c)
  })
  var names = Object.keys(projects)
  names.forEach(function (n) {
    projects[n].sort(function (a, b) { return RANK[a.state] - RANK[b.state] || (a.title < b.title ? -1 : 1) })
  })
  names.sort(function (a, b) { return RANK[projects[a][0].state] - RANK[projects[b][0].state] || (a < b ? -1 : 1) })
  var rows = [{ key: 'm:' + host, kind: 'machine', title: host, stText: 'this machine', count: String(cards.length) }]
  names.forEach(function (n) {
    rows.push({ key: 'p:' + host + '/' + n, kind: 'project', title: n, count: String(projects[n].length) })
    projects[n].forEach(function (c) { rows.push(c) })
  })
  return {
    host: host,
    needCount: cards.filter(function (c) { return c.state === 'needs' }).length,
    total: cards.length,
    weekly: weekly(feeds),
    rows: rows
  }
}
