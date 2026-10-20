import { expect, test } from 'claude-code/testing'

import { RULES, isMode, switchNote } from './brief'
import {
  type Snapshot, type Timing, MAX_TOKENS, SOURCE,
  activityFor, applyTaskCall, str, clearArgs, emptySnapshot, feedJson, gitFacts, isTitleSource, metadataArgs, modelName,
  planCounts, planFromTodos, resultLine, shorten, stateForNotification, titleFrom, todosFromBook, tokens,
} from './feed'

const snapshot = (over: Partial<Snapshot> = {}): Snapshot => ({
  ...emptySnapshot(),
  machine: 'workstation', project: 'acme-site', branch: 'fix/post-hang', model: 'Opus 5.5', title: 'Fix Vercel POST hang',
  state: 'working', started: 1_000_000, since: 1_060_000, context: 62.4, limit: 34, limitReset: 1_000_000 + 8_100_000,
  weekly: 41, last: 'The form works again.', ...over,
})

const tok = (s: Snapshot): Record<string, string> => Object.fromEntries(tokens(s))

test('shorten cuts at a word and adds an ellipsis', () => {
  expect(shorten('short')).toBe('short')
  const cut = shorten('word '.repeat(40), 30)
  expect(cut.length).toBeLessThanOrEqual(30)
  expect(cut.endsWith('…')).toBe(true)
  expect(cut).not.toContain('  ')
})

test('titleFrom takes the first line with words, without markdown', () => {
  expect(titleFrom('\n\n## Fix the **Vercel** POST hang\nMore text')).toBe('Fix the Vercel POST hang')
  expect(titleFrom('Fix `the` hang '.repeat(10)).length).toBeLessThanOrEqual(60)
  expect(titleFrom('```\ncode only\n```')).toBe('')
})

test('isTitleSource skips slash commands and automatic prompts', () => {
  expect(isTitleSource('Fix the hang', 'user')).toBe(true)
  expect(isTitleSource('Fix the hang')).toBe(true)
  expect(isTitleSource('/brief')).toBe(false)
  expect(isTitleSource('check again', 'loop_wakeup')).toBe(false)
  expect(isTitleSource('   ')).toBe(false)
})

test('resultLine is the first line with words', () => {
  expect(resultLine('\n**Done.** The form works again.\n\nFiles: a.ts')).toBe('Done. The form works again.')
  expect(resultLine('')).toBe('')
})

test('modelName reads model ids', () => {
  expect(modelName('claude-opus-5-5')).toBe('Opus 5.5')
  expect(modelName('claude-fable-5-1')).toBe('Fable 5.1')
  expect(modelName('claude-sonnet-4-5-20250929')).toBe('Sonnet 4.5')
  expect(modelName('claude-haiku-5')).toBe('Haiku 5')
  expect(modelName('claude-3-5-sonnet-20241022')).toBe('Sonnet 3.5')
  expect(modelName('claude-opus-5-5[1m]')).toBe('Opus 5.5')
  expect(modelName('my-gateway-model')).toBe('my-gateway-model')
  expect(modelName(undefined)).toBe('')
})

test('gitFacts gives the repository name for a worktree and the branch', () => {
  expect(gitFacts('/srv/work/herdr-graphite/.git\nmain\n', '/srv/work/herdr-graphite-H2'))
    .toEqual({ project: 'herdr-graphite', branch: 'main' })
  expect(gitFacts('/srv/git/acme-site.git\nfix/x\n', '/work/acme-site')).toEqual({ project: 'acme-site', branch: 'fix/x' })
  expect(gitFacts('/a/b/.git\nHEAD\n', '/a/b').branch).toBe('detached')
  expect(gitFacts('', '/srv/work/notes')).toEqual({ project: 'notes', branch: '' })
})

test('planFromTodos counts steps and times a step from running to done', () => {
  const timing: Timing = new Map()
  const todos = (a: string, b: string) => ({
    todos: [
      { content: 'Read the form code', status: a, activeForm: 'Reading the form code' },
      { content: 'Fix it', status: b, activeForm: 'Fixing it' },
      { content: 'Ship it', status: b === 'pending' ? 'pending' : 'completed', activeForm: 'Shipping it' },
    ],
  })
  let plan = planFromTodos(todos('in_progress', 'pending'), timing, 10_000)
  expect(plan.map(p => p.status)).toEqual(['now', 'next', 'next'])
  expect(planCounts(plan)).toEqual({ done: 0, total: 3, step: 'Read the form code', doing: 'Reading the form code' })
  plan = planFromTodos(todos('completed', 'in_progress'), timing, 30_000)
  expect(plan.map(p => p.status)).toEqual(['done', 'now', 'done'])
  expect(plan[0]?.seconds).toBe(20)
  expect(plan[2]?.seconds).toBeNull() // never seen running
  plan = planFromTodos(todos('completed', 'completed'), timing, 60_000)
  expect(plan[1]?.seconds).toBe(30)
  expect(planCounts(plan)).toEqual({ done: 3, total: 3, step: '', doing: '' })
})

test('planFromTodos ignores wrong input', () => {
  const timing: Timing = new Map()
  expect(planFromTodos(undefined, timing, 0)).toEqual([])
  expect(planFromTodos({ todos: 'x' }, timing, 0)).toEqual([])
  expect(planFromTodos({ todos: [null, { status: 'pending' }, {}] }, timing, 0)).toEqual([])
})

test('the task book makes a plan from TaskCreate and TaskUpdate', () => {
  const book = new Map()
  applyTaskCall(book, 'TaskCreate', { subject: 'Find the cause', description: '', activeForm: 'Finding the cause' }, { task: { id: '1', subject: 'Find the cause' } })
  applyTaskCall(book, 'TaskCreate', { subject: 'Fix it', description: '' }, 'Task #2 created')
  applyTaskCall(book, 'TaskUpdate', { taskId: '1', status: 'completed' }, {})
  applyTaskCall(book, 'TaskUpdate', { taskId: '2', status: 'in_progress' }, {})
  applyTaskCall(book, 'TaskUpdate', { taskId: '9', status: 'in_progress' }, {}) // unknown id
  const plan = planFromTodos(todosFromBook(book), new Map(), 0)
  expect(plan.map(p => `${p.name}:${p.status}`)).toEqual(['Find the cause:done', 'Fix it:now'])
  expect(plan.map(p => p.doing)).toEqual(['Finding the cause', 'Fix it'])
  applyTaskCall(book, 'TaskUpdate', { taskId: '2', status: 'deleted' }, {})
  expect(book.size).toBe(1)
})

test('activityFor names the work in a short phrase', () => {
  expect(activityFor('Edit', { file_path: '/a/b/feed.ts' })).toBe('Editing feed.ts')
  expect(activityFor('Bash', { command: 'pnpm test\nsecond', description: 'Run the tests' })).toBe('Running Run the tests')
  expect(activityFor('Bash', { command: 'pnpm test' })).toBe('Running pnpm test')
  expect(activityFor('Grep', {})).toBe('Searching the code')
  expect(activityFor('mcp__figma__get_design', {})).toBe('Using figma')
  expect(activityFor('Foo', null)).toBe('Using Foo')
})

test('stateForNotification', () => {
  expect(stateForNotification('permission_prompt')).toBe('needs')
  expect(stateForNotification('elicitation_dialog')).toBe('needs')
  expect(stateForNotification('idle_prompt')).toBe('done')
})

test('tokens carry the fields of the v2 session card', () => {
  const plan = planFromTodos({ todos: [
    { content: 'Read', status: 'completed', activeForm: 'Reading' },
    { content: 'Fix', status: 'in_progress', activeForm: 'Fixing' },
    { content: 'Test', status: 'pending', activeForm: 'Testing' },
  ] }, new Map(), 0)
  const t = tok(snapshot({ plan }))
  expect(t).toEqual({
    state: 'working', machine: 'workstation', project: 'acme-site', branch: 'fix/post-hang', model: 'Opus 5.5', mode: 'brief',
    step: 'Fixing', steps: 'dnp', context: '62', limit: '34', limit_reset: '9100', weekly: '41',
    last: 'The form works again.', ask: '', started: '1000', since: '1060',
  })
})

test('a report holds at most 16 tokens, the most that herdr takes', () => {
  expect(tokens(snapshot()).length).toBeLessThanOrEqual(MAX_TOKENS)
  expect(new Set(tokens(snapshot()).map(([n]) => n)).size).toBe(tokens(snapshot()).length)
})

test('tokens: empty values clear, the ask shows only while the agent needs you', () => {
  const t = tok(emptySnapshot())
  expect(t.steps).toBe('')
  expect(t.context).toBe('')
  expect(t.limit_reset).toBe('')
  expect(tok(snapshot({ state: 'working', ask: 'Allow Bash?' })).ask).toBe('')
  expect(tok(snapshot({ state: 'needs', ask: 'Allow Bash?' })).ask).toBe('Allow Bash?')
  expect(tok(snapshot({ context: 140 })).context).toBe('100')
  expect(tok(snapshot({ limit: -3 })).limit).toBe('0')
})

test('every token value and label stays within the 80 characters that herdr keeps', () => {
  const long = 'word '.repeat(60)
  const args = metadataArgs(snapshot({ last: long, ask: long, activity: long, state: 'needs', title: titleFrom(long) }), 1)
  for (const a of args) expect(a.length).toBeLessThanOrEqual(86) // "name=" plus 80
})

test('metadataArgs: source, seq, title, state labels and tokens, as separate arguments', () => {
  const args = metadataArgs(snapshot({ activity: 'Editing feed.ts' }), 42)
  expect(args.slice(0, 5)).toEqual(['--source', SOURCE, '--seq', '42', '--title'])
  expect(args[5]).toBe('Fix Vercel POST hang')
  expect(args.some(a => a.startsWith('--') && a.includes('='))).toBe(false) // herdr takes "--flag value" only
  const pairs = args.slice(6)
  expect(pairs).toContain('working=Editing feed.ts')
  expect(pairs).toContain('blocked=Needs you')
  expect(pairs).toContain('done=Done')
  expect(pairs).toContain('idle=Idle')
  expect(pairs).toContain('state=working')
  expect(pairs).toContain('branch=fix/post-hang')
})

test('metadataArgs: no title flag without a title; failed and ready show in the idle label', () => {
  expect(metadataArgs(snapshot({ title: '' }), 1)).not.toContain('--title')
  expect(metadataArgs(snapshot({ title: '' }), 1)).toContain('--clear-title') // herdr may hold an old title
  expect(metadataArgs(snapshot({ state: 'failed' }), 1)).toContain('idle=Failed')
  expect(metadataArgs(snapshot({ state: 'ready' }), 1)).toContain('idle=Ready')
  expect(metadataArgs(snapshot({ state: 'needs', ask: 'Wants to run: git push' }), 1)).toContain('blocked=Wants to run: git push')
})

test('clearArgs clears the title, the labels and every token', () => {
  const args = clearArgs(9)
  expect(args).toContain('--clear-title')
  expect(args).toContain('--clear-state-labels')
  const cleared = args.filter((a, i) => args[i - 1] === '--clear-token')
  expect(cleared.sort()).toEqual(tokens(emptySnapshot()).map(([n]) => n).sort())
})

test('feedJson holds the whole plan for the app', () => {
  const plan = planFromTodos({ todos: [{ content: 'Read', status: 'completed', activeForm: 'Reading' }] }, new Map(), 0)
  const j = JSON.parse(feedJson(snapshot({ plan }), 'wK:p1', 'sess-1', '/w/acme-site', 2_000_000))
  expect(j.version).toBe(1)
  expect(j.pane).toBe('wK:p1')
  expect(j.state).toBe('working')
  expect(j.state_label).toBe('Working')
  expect(j.limit_reset).toBe(9100)
  expect(j.plan).toEqual({ done: 1, total: 1, step: '', doing: '', items: [{ name: 'Read', doing: 'Reading', status: 'done', seconds: null }] })
})

test('the feed functions survive wrong input', () => {
  expect(shorten(undefined as never)).toBe('')
  expect(titleFrom(undefined as never)).toBe('')
  expect(resultLine(null as never)).toBe('')
  expect(isTitleSource(undefined as never)).toBe(false)
  expect(str(5)).toBe('')
  expect(str('x')).toBe('x')
  expect(() => metadataArgs({ ...snapshot(), ask: undefined as never, last: undefined as never, activity: undefined as never }, 1)).not.toThrow()
})

test('the weekly reset is in the feed file only', () => {
  const j = JSON.parse(feedJson(snapshot({ weeklyReset: 5_000_000 }), 'p', 's', '/c', 6_000_000))
  expect(j.weekly_reset).toBe(5000)
  expect(tokens(snapshot()).map(([n]) => n)).not.toContain('weekly_reset') // the 16 tokens are full
  expect(JSON.parse(feedJson(snapshot(), 'p', 's', '/c', 0)).weekly_reset).toBeNull()
})

test('the Brief rule is for chat replies only, and asks for no offer to say more', () => {
  const brief = RULES.brief
  expect(brief).toContain('for chat replies only')
  expect(brief).toContain('Files, documents, reports, briefs, handoffs, reviews, commit messages and pull request text are written in full')
  expect(brief).toContain('asks for a full report or for a fixed report form, give it in full')
  expect(brief).toContain('That request comes before this rule')
  expect(brief).toContain('Do not end with an offer to say more')
  expect(brief).not.toMatch(/offer (it|more|to say more)\.?\s*$/m) // no line that tells the model to offer more
  expect(brief).not.toContain('When the answer needs more room')
  expect(RULES.full).toContain('written in full')
  expect(RULES.full).toContain('That request comes before this rule')
})

test('the reply rules: modes, the Files and Tests form, the switch note', () => {
  expect(isMode('brief') && isMode('normal') && isMode('full')).toBe(true)
  expect(isMode('loud')).toBe(false)
  expect(RULES.brief).toContain('at most 3 lines of prose')
  expect(RULES.brief).toContain('Files:')
  expect(RULES.brief).toContain('Tests:')
  expect(RULES.normal).toContain('Ignore any earlier instruction')
  expect(switchNote('full')).toContain('Reply style: Full.')
})
