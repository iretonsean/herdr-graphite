// The data feed: pure functions that turn Claude Code hook data into the arguments of
// `herdr pane report-metadata` and into the JSON file for the Graphite app. No I/O here, so the tests
// run them with sample JSON.
//
// The fields follow the session cards of the v2 prototype (Main and Command): machine, project, branch,
// title, state, model, plan steps, context %, session limit %, weekly limit %, last message line, time.

/** The states of the cards. They are the keys of the prototype: ready, working, needs, done, failed. */
export type FeedState = 'ready' | 'working' | 'needs' | 'done' | 'failed'

export type PlanItem = {
  name: string
  /** The step as it reads while it runs: "Reading the form code". */
  doing: string
  status: 'done' | 'now' | 'next'
  /** How long the step took, in seconds. Null while it runs, and for a step that was never seen running. */
  seconds: number | null
}

export type Snapshot = {
  /** The host name of this machine. */
  machine: string
  /** The project: the name of the git repository folder (the main one, for a worktree). */
  project: string
  branch: string
  /** "Opus 5.5". */
  model: string
  title: string
  /** The reply style of the session: brief, normal or full. */
  mode: string
  state: FeedState
  /** When the session started, in ms since the epoch. */
  started: number
  /** When the state last changed, in ms since the epoch. "Waiting 4 min" is now minus this. */
  since: number
  /** What the agent does now, for the "working" label: "Editing feed.ts". */
  activity: string
  plan: PlanItem[]
  /** Context window use in percent, 0 to 100. */
  context: number | null
  /** 5-hour session limit use in percent. */
  limit: number | null
  /** When the 5-hour window resets, in ms since the epoch. */
  limitReset: number | null
  /** Weekly (7-day) limit use in percent. */
  weekly: number | null
  /** When the weekly window resets, in ms since the epoch. */
  weeklyReset: number | null
  /** The result line of the last message. */
  last: string
  /** What the agent waits for ("Allow Bash?"), for the "needs" label. */
  ask: string
}

export const SOURCE = 'graphite'
/** herdr cuts every text at 80 characters. Stay below, so that nothing ends in the middle of a word. */
export const MAX = 76
const TITLE_MAX = 60
/** One character per step in the `steps` token: d done, n now, p pending. herdr cuts a token at 80. */
const STEPS_MAX = 76

/** A hook input field as text. A missing or wrong-type field becomes an empty string, never a crash. */
export const str = (v: unknown): string => (typeof v === 'string' ? v : '')

export const emptySnapshot = (): Snapshot => ({
  machine: '', project: '', branch: '', model: '', title: '', mode: 'brief', state: 'ready', started: 0, since: 0,
  activity: '', plan: [], context: null, limit: null, limitReset: null, weekly: null, weeklyReset: null, last: '', ask: '',
})

/** Cut a text at a word boundary and add "…". */
export function shorten(text: string, max = MAX): string {
  const flat = str(text).replace(/\s+/g, ' ').trim()
  if (flat.length <= max) return flat
  const cut = flat.slice(0, max - 1)
  const space = cut.lastIndexOf(' ')
  return `${(space > max * 0.5 ? cut.slice(0, space) : cut).replace(/[\s,;:.-]+$/, '')}…`
}

/** Remove the markdown marks that make a title or a line hard to read: `code`, **bold**, # head, - list, > quote. */
export function plain(text: string): string {
  return str(text)
    .replace(/```[\s\S]*?```/g, ' ')
    .replace(/!?\[([^\]]*)\]\([^)]*\)/g, '$1')
    .replace(/^\s{0,3}(?:#{1,6}|[-*+>]|\d+[.)])\s+/, '')
    .replace(/[`*_~]/g, '')
    .replace(/\s+/g, ' ')
    .trim()
}

/** The title of a session from its first prompt: the first line that has words, short. */
export function titleFrom(prompt: string): string {
  const line = str(prompt).replace(/```[\s\S]*?```/g, '\n').split('\n').map(plain).find(l => /\w/.test(l)) ?? ''
  return shorten(line, TITLE_MAX)
}

/** A prompt that can name the session. A slash command or an automatic wake-up cannot. */
export function isTitleSource(prompt: string, source?: string): boolean {
  if (source !== undefined && source !== 'user') return false
  const p = str(prompt)
  return !p.trimStart().startsWith('/') && /\w/.test(p)
}

/** The result line of a message: the first line with words, without markdown. Short replies put the result first. */
export function resultLine(message: string): string {
  const line = str(message).replace(/```[\s\S]*?```/g, '\n').split('\n').map(plain).find(l => /\w/.test(l)) ?? ''
  return shorten(line)
}

/** "claude-opus-5-5" becomes "Opus 5.5". An id that has no known form is returned as it is. */
export function modelName(id: string | undefined): string {
  if (!id) return ''
  const clean = id.replace(/\[.*\]$/, '').trim()
  const word = (s: string): string => s.charAt(0).toUpperCase() + s.slice(1)
  const a = /^claude-([a-z]+)-(\d+)(?:-(\d{1,2}))?(?:-\d{8})?$/.exec(clean)
  if (a?.[1] && a[2]) return `${word(a[1])} ${a[2]}${a[3] ? `.${a[3]}` : ''}`
  const b = /^claude-(\d+)(?:-(\d{1,2}))?-([a-z]+)/.exec(clean)
  if (b?.[3] && b[1]) return `${word(b[3])} ${b[1]}${b[2] ? `.${b[2]}` : ''}`
  return shorten(clean, 24)
}

/**
 * The project and branch from `git rev-parse --path-format=absolute --git-common-dir --abbrev-ref HEAD`
 * (two lines). The common dir is the main repository's .git folder, also inside a worktree, so a worktree
 * has the project name of its repository. Outside a repository the project is the folder name.
 */
export function gitFacts(output: string, cwd: string): { project: string; branch: string } {
  const [common = '', head = ''] = output.split('\n').map(l => l.trim())
  const folderName = (p: string): string => p.split('/').filter(Boolean).pop() ?? ''
  let project = folderName(cwd)
  if (common.endsWith('/.git')) project = folderName(common.slice(0, -5))
  else if (common.endsWith('.git') && common !== '') project = folderName(common).replace(/\.git$/, '')
  const branch = head === 'HEAD' ? 'detached' : head
  return { project, branch }
}

// --- Plan -------------------------------------------------------------------------------------------

type Todo = { content?: unknown; status?: unknown; activeForm?: unknown }

/** The time a step took, by the name of the step. The register module keeps one for the session. */
export type Timing = Map<string, { start: number; seconds: number | null }>

/**
 * The plan items of a TodoWrite call (or of the todo list that a task book makes), with the time each step took.
 * The time is the gap between the call that first showed the step running and the call that showed it done.
 * Returns an empty list for an empty or wrong input.
 */
export function planFromTodos(input: unknown, timing: Timing, now: number): PlanItem[] {
  const todos = (input as { todos?: unknown } | null | undefined)?.todos
  if (!Array.isArray(todos)) return []
  const items: PlanItem[] = []
  for (const t of todos as Todo[]) {
    const name = shorten(plain(String(t?.content ?? t?.activeForm ?? '')), 60)
    if (name === '') continue
    const doing = typeof t?.activeForm === 'string' && t.activeForm !== '' ? shorten(plain(t.activeForm), 60) : name
    const t0 = timing.get(name)
    if (t?.status === 'completed') {
      if (t0 !== undefined && t0.seconds === null) t0.seconds = Math.max(0, Math.round((now - t0.start) / 1000))
      items.push({ name, doing, status: 'done', seconds: t0?.seconds ?? null })
    } else if (t?.status === 'in_progress') {
      if (t0 === undefined) timing.set(name, { start: now, seconds: null })
      items.push({ name, doing, status: 'now', seconds: null })
    } else {
      items.push({ name, doing, status: 'next', seconds: null })
    }
  }
  return items
}

/** The tasks of TaskCreate and TaskUpdate calls, for a session that uses these tools instead of TodoWrite. */
export type TaskBook = Map<string, { subject: string; activeForm: string; status: string }>

/** Apply one TaskCreate or TaskUpdate call to the book. `response` is what the tool returned (any shape). */
export function applyTaskCall(book: TaskBook, tool: string, input: unknown, response: unknown): void {
  const i = (input ?? {}) as Record<string, unknown>
  if (tool === 'TaskCreate') {
    const id = taskIdFrom(response)
    if (id !== undefined) book.set(id, { subject: String(i.subject ?? ''), activeForm: String(i.activeForm ?? ''), status: 'pending' })
  } else if (tool === 'TaskUpdate') {
    const id = String(i.taskId ?? '')
    const task = book.get(id)
    if (i.status === 'deleted') book.delete(id)
    else if (task !== undefined) {
      if (typeof i.status === 'string') task.status = i.status
      if (typeof i.subject === 'string') task.subject = i.subject
      if (typeof i.activeForm === 'string') task.activeForm = i.activeForm
    }
  }
}

function taskIdFrom(response: unknown): string | undefined {
  const r = response as { task?: { id?: unknown }; id?: unknown } | string | null | undefined
  if (r !== null && typeof r === 'object') {
    const id = r.task?.id ?? r.id
    if (typeof id === 'string' || typeof id === 'number') return String(id)
  }
  return /#(\d+)/.exec(typeof r === 'string' ? r : JSON.stringify(r ?? ''))?.[1]
}

/** The book as a TodoWrite input, so one function makes the plan items. */
export const todosFromBook = (book: TaskBook): { todos: Todo[] } => ({
  todos: [...book.values()].map(t => ({ content: t.subject, activeForm: t.activeForm, status: t.status })),
})

export function planCounts(plan: readonly PlanItem[]): { done: number; total: number; step: string; doing: string } {
  const now = plan.find(p => p.status === 'now') ?? plan.find(p => p.status === 'next')
  return { done: plan.filter(p => p.status === 'done').length, total: plan.length, step: now?.name ?? '', doing: now?.doing ?? '' }
}

// --- Words for the card -----------------------------------------------------------------------------

/** What a tool call looks like in one short phrase: "Editing feed.ts", "Running tests". */
export function activityFor(tool: string, input: unknown): string {
  const i = (input ?? {}) as Record<string, unknown>
  const file = typeof i.file_path === 'string' ? i.file_path.split('/').pop() ?? '' : ''
  switch (tool) {
    case 'Read': return `Reading ${file}`.trim()
    case 'Edit': case 'MultiEdit': return `Editing ${file}`.trim()
    case 'Write': return `Writing ${file}`.trim()
    case 'NotebookEdit': return 'Editing a notebook'
    case 'Bash': {
      const desc = typeof i.description === 'string' && i.description !== '' ? i.description : String(i.command ?? '').split('\n')[0] ?? ''
      return shorten(`Running ${desc}`.trim(), 50)
    }
    case 'Grep': case 'Glob': return 'Searching the code'
    case 'WebFetch': case 'WebSearch': return 'Searching the web'
    case 'Task': case 'Agent': return 'Running a subagent'
    case 'TodoWrite': case 'TaskCreate': case 'TaskUpdate': return 'Updating the plan'
    default: return tool.startsWith('mcp__') ? `Using ${tool.split('__')[1] ?? 'a tool'}` : `Using ${tool}`
  }
}

/** The state that a Notification hook means. A permission prompt or a question needs you; an idle prompt is "done". */
export function stateForNotification(type: string): FeedState {
  return type === 'idle_prompt' ? 'done' : 'needs'
}

const LABEL: Record<FeedState, string> = {
  ready: 'Ready', working: 'Working', needs: 'Needs you', done: 'Done', failed: 'Failed',
}
export const stateLabel = (s: FeedState): string => LABEL[s]

// --- Output -----------------------------------------------------------------------------------------

const pct = (n: number | null): string => (n === null ? '' : String(Math.max(0, Math.min(100, Math.round(n)))))
const secs = (ms: number | null): string => (ms === null || ms <= 0 ? '' : String(Math.floor(ms / 1000)))

/** One character per step: d done, n now, p pending. */
export const stepsString = (plan: readonly PlanItem[]): string =>
  plan.map(p => (p.status === 'done' ? 'd' : p.status === 'now' ? 'n' : 'p')).join('').slice(0, STEPS_MAX)

/**
 * The tokens of one report, in order. An empty value clears the token in herdr. Token names use letters and
 * underscore, so a sidebar row can read them as `$name`. herdr accepts at most 16 tokens in one report, so the
 * plan count ("2 of 5") is not a token: it is the d and n characters of `steps` against its length.
 */
/** The most tokens that herdr takes in one report. */
export const MAX_TOKENS = 16

export function tokens(s: Snapshot): [name: string, value: string][] {
  const c = planCounts(s.plan)
  return [
    ['state', s.state],
    ['machine', s.machine],
    ['project', s.project],
    ['branch', s.branch],
    ['model', s.model],
    ['mode', s.mode],
    ['step', c.doing],
    ['steps', stepsString(s.plan)],
    ['context', pct(s.context)],
    ['limit', pct(s.limit)],
    ['limit_reset', secs(s.limitReset)],
    ['weekly', pct(s.weekly)],
    ['last', shorten(s.last)],
    ['ask', s.state === 'needs' ? shorten(s.ask) : ''],
    ['started', secs(s.started)],
    ['since', secs(s.since)],
  ]
}

/**
 * The arguments that follow `report-metadata <pane>`. One call carries the whole picture, so a late or lost
 * report never leaves a half state. herdr's CLI takes `--flag value` only (not `--flag=value`).
 */
export function metadataArgs(s: Snapshot, seq: number): string[] {
  const c = planCounts(s.plan)
  const working = s.activity !== '' ? s.activity : c.doing !== '' ? c.doing : 'Working'
  const args = ['--source', SOURCE, '--seq', String(seq)]
  // No title: clear the one that herdr may still hold (after /clear, for example).
  if (s.title !== '') args.push('--title', s.title)
  else args.push('--clear-title')
  const labels: [string, string][] = [
    ['working', shorten(working)],
    ['blocked', s.ask !== '' ? shorten(s.ask) : 'Needs you'],
    ['done', 'Done'],
    ['idle', s.state === 'failed' ? 'Failed' : s.state === 'ready' ? 'Ready' : 'Idle'],
  ]
  for (const [status, text] of labels) args.push('--state-label', `${status}=${text}`)
  for (const [name, value] of tokens(s)) args.push('--token', `${name}=${value}`)
  return args
}

/** The arguments that remove everything this source set, for a session that ends. */
export function clearArgs(seq: number): string[] {
  const args = ['--source', SOURCE, '--seq', String(seq), '--clear-title', '--clear-state-labels']
  for (const [name] of tokens(emptySnapshot())) args.push('--clear-token', name)
  return args
}

/** The file for the Graphite app: everything in the snapshot, with the full plan. */
export function feedJson(s: Snapshot, pane: string, sessionId: string, cwd: string, now: number): string {
  const c = planCounts(s.plan)
  return JSON.stringify({
    version: 1, pane, session_id: sessionId, cwd, updated: Math.floor(now / 1000),
    machine: s.machine, project: s.project, branch: s.branch, model: s.model, title: s.title, mode: s.mode,
    state: s.state, state_label: stateLabel(s.state), activity: s.activity, ask: s.ask, last: s.last,
    started: Math.floor(s.started / 1000), since: Math.floor(s.since / 1000),
    plan: { done: c.done, total: c.total, step: c.step, doing: c.doing, items: s.plan },
    context: s.context, limit: s.limit, limit_reset: s.limitReset === null ? null : Math.floor(s.limitReset / 1000), weekly: s.weekly,
    weekly_reset: s.weeklyReset === null ? null : Math.floor(s.weeklyReset / 1000),
  })
}
