import type { On } from 'claude-code'
import { expect, mock, test } from 'claude-code/testing'

const PANE = 'wK:p1P'
const BASE = { session_id: 'sess-1', transcript_path: '/t.jsonl', cwd: '/w/acme-site' }
const RUN_OK = { exitCode: 0, stderr: '', isStdoutTruncated: false, isStderrTruncated: false }

type Call = { argv: readonly string[]; stdin?: string }

const CLASSIC = ['SessionStart', 'UserPromptSubmit', 'PostToolUse', 'Notification', 'Stop', 'StopFailure', 'SessionEnd'] as const

/** The world beneath the plugin: env, clock, `process.run` and `session.usage` answered from tables. Returns the herdr calls. */
function world(on: On, env: Record<string, string> = { HERDR_ENV: '1', HERDR_PANE_ID: PANE }) {
  const calls: Call[] = []
  mock.env(on, env)
  const clock = mock.clock(on, { now: 1_000_000 })
  // The engine's own end of each classic hook: nothing to add.
  for (const name of CLASSIC) on(`classic.${name}`, () => ({}))
  on('process.run', (_$, e) => {
    if (e.argv[0] === 'hostname') return { value: { ...RUN_OK, stdout: 'workstation\n' } }
    if (e.argv[0] === 'git') return { value: { ...RUN_OK, stdout: '/w/acme-site/.git\nfix/post-hang\n' } }
    calls.push({ argv: e.argv, stdin: e.init?.stdin })
    return { value: { ...RUN_OK, stdout: '' } }
  })
  on('session.usage', () => ({
    value: {
      startedAt: 0,
      context: { window: 200000, percent: 62.4 },
      rateLimits: [
        { kind: 'five_hour', percentUsed: 34, resetsAt: '2026-10-19T20:00:00.000Z' },
        { kind: 'seven_day', percentUsed: 41 },
      ],
    },
  }))
  return { calls, clock }
}

/** The herdr arguments of one report as a map: tokens, labels and the title. */
function read(call: Call) {
  const a = call.argv.slice(6) // sh -c SCRIPT sh verb pane
  const out = { verb: call.argv[4], pane: call.argv[5], tokens: {} as Record<string, string>, labels: {} as Record<string, string>, title: '', flags: [] as string[] }
  for (let i = 0; i < a.length; i++) {
    const f = a[i] ?? ''
    if (f === '--token' || f === '--state-label') {
      const v = a[++i] ?? ''
      const k = v.slice(0, v.indexOf('='))
      ;(f === '--token' ? out.tokens : out.labels)[k] = v.slice(v.indexOf('=') + 1)
    } else if (f === '--title') out.title = a[++i] ?? ''
    else out.flags.push(f)
  }
  return out
}

test('outside herdr the feed does nothing', async ($, on) => {
  const w = world(on, {})
  await $.classic.SessionStart({ ...BASE, source: 'startup' })
  await $.classic.UserPromptSubmit({ ...BASE, prompt: 'Fix the hang' })
  await $.classic.Stop({ ...BASE, stop_hook_active: false, last_assistant_message: 'Done.' })
  expect(w.calls.length).toBe(0)
})

test('SessionStart reports machine, project, branch, model, context and limits', async ($, on) => {
  const w = world(on)
  await $.classic.SessionStart({ ...BASE, source: 'startup', model: 'claude-opus-5-5' })
  expect(w.calls.length).toBe(1)
  const r = read(w.calls[0]!)
  expect(r.verb).toBe('write')
  expect(r.pane).toBe(PANE)
  expect(r.tokens).toMatchObject({
    state: 'ready', machine: 'workstation', project: 'acme-site', branch: 'fix/post-hang', model: 'Opus 5.5',
    context: '62', limit: '34', weekly: '41', started: '1000', mode: 'brief',
  })
  expect(Number(r.tokens.limit_reset)).toBeGreaterThan(0)
  expect(r.flags).toContain('--source')
  // The same report goes to the file for the app.
  const file = JSON.parse(w.calls[0]!.stdin!)
  expect(file.pane).toBe(PANE)
  expect(file.project).toBe('acme-site')
})

test('a prompt sets the title and "working"; later prompts keep the title', async ($, on) => {
  const w = world(on)
  await $.classic.SessionStart({ ...BASE, source: 'startup' })
  await $.classic.UserPromptSubmit({ ...BASE, prompt: '/brief' })
  expect(read(w.calls.at(-1)!).title).toBe('') // a slash command names nothing
  await $.classic.UserPromptSubmit({ ...BASE, prompt: 'Fix the Vercel POST hang\nLong story follows.' })
  let r = read(w.calls.at(-1)!)
  expect(r.title).toBe('Fix the Vercel POST hang')
  expect(r.tokens.state).toBe('working')
  await $.classic.UserPromptSubmit({ ...BASE, prompt: 'Now something else' })
  r = read(w.calls.at(-1)!)
  expect(r.title).toBe('Fix the Vercel POST hang')
})

test('the task name of the agent replaces the prompt title', async ($, on) => {
  const w = world(on)
  await $.classic.UserPromptSubmit({ ...BASE, prompt: 'Fix the hang', session_title: 'POST hang on Vercel' })
  expect(read(w.calls.at(-1)!).title).toBe('POST hang on Vercel')
})

test('Stop reports "done" and the result line; StopFailure reports "failed"', async ($, on) => {
  const w = world(on)
  await $.classic.UserPromptSubmit({ ...BASE, prompt: 'Fix the hang' })
  await $.classic.Stop({ ...BASE, stop_hook_active: false, last_assistant_message: 'The form works again.\n\nFiles: app/route.ts' })
  let r = read(w.calls.at(-1)!)
  expect(r.tokens).toMatchObject({ state: 'done', last: 'The form works again.' })
  await $.classic.StopFailure({ ...BASE, error: 'rate_limit', error_details: 'Limit reached' })
  r = read(w.calls.at(-1)!)
  expect(r.tokens.state).toBe('failed')
  expect(r.labels.idle).toBe('Failed')
})

test('Notification: a permission prompt "needs" you with the ask; an idle prompt is "done"', async ($, on) => {
  const w = world(on)
  await $.classic.Notification({ ...BASE, message: 'Claude needs your permission to use Bash', notification_type: 'permission_prompt' })
  let r = read(w.calls.at(-1)!)
  expect(r.tokens.state).toBe('needs')
  expect(r.tokens.ask).toBe('Claude needs your permission to use Bash')
  expect(r.labels.blocked).toBe('Claude needs your permission to use Bash')
  await $.classic.Notification({ ...BASE, message: 'Claude is waiting for your input', notification_type: 'idle_prompt' })
  r = read(w.calls.at(-1)!)
  expect(r.tokens.state).toBe('done')
  expect(r.tokens.ask).toBe('')
})

test('PostToolUse with a todo list reports the plan at once', async ($, on) => {
  const w = world(on)
  await $.classic.PostToolUse({
    ...BASE, tool_name: 'TodoWrite', tool_use_id: 't1', tool_response: {},
    tool_input: { todos: [
      { content: 'Read the form code', status: 'completed', activeForm: 'Reading the form code' },
      { content: 'Find the cause', status: 'in_progress', activeForm: 'Finding the cause' },
    ] },
  })
  const r = read(w.calls.at(-1)!)
  expect(r.tokens).toMatchObject({ step: 'Finding the cause', steps: 'dn' })
  expect(JSON.parse(w.calls.at(-1)!.stdin!).plan.items.length).toBe(2)
})

test('tool events are light: one report per throttle time, and none when nothing changed', async ($, on) => {
  const w = world(on)
  on('tool.call', () => ({ result: 'ok', text: 'ok', isError: false, isReadOnly: true }) as never)
  await $.classic.UserPromptSubmit({ ...BASE, prompt: 'Fix the hang' })
  const base = w.calls.length
  await $.tool.call({ tool: 'Read', tool_use_id: 'a', file_path: '/w/a.ts' } as never)
  expect(w.calls.length).toBe(base) // inside the throttle time
  await w.clock.advance(2000)
  await $.tool.call({ tool: 'Read', tool_use_id: 'b', file_path: '/w/b.ts' } as never)
  expect(w.calls.length).toBe(base + 1)
  expect(read(w.calls.at(-1)!).labels.working).toBe('Reading b.ts')
  await w.clock.advance(2000)
  await $.tool.call({ tool: 'Read', tool_use_id: 'c', file_path: '/w/b.ts' } as never)
  expect(w.calls.length).toBe(base + 1) // same picture: nothing sent
})

test('SessionEnd clears what the feed set', async ($, on) => {
  const w = world(on)
  await $.classic.SessionEnd({ ...BASE, reason: 'other' } as never)
  const r = read(w.calls.at(-1)!)
  expect(r.verb).toBe('clear')
  expect(r.flags).toContain('--clear-state-labels')
})

test('seq grows with every report, even in the same millisecond', async ($, on) => {
  const w = world(on)
  await $.classic.Stop({ ...BASE, stop_hook_active: false })
  await $.classic.Stop({ ...BASE, stop_hook_active: false })
  const seqs = w.calls.map(c => Number(c.argv[c.argv.indexOf('--seq') + 1]))
  expect(seqs[1]!).toBeGreaterThan(seqs[0]!)
})

test('a failing herdr call never breaks the hook or the session', async ($, on) => {
  mock.env(on, { HERDR_ENV: '1', HERDR_PANE_ID: PANE })
  mock.clock(on, { now: 5 })
  on('classic.Stop', () => ({}))
  on('process.run', () => { throw new Error('herdr is gone') })
  on('session.usage', () => { throw new Error('no usage') })
  await $.classic.Stop({ ...BASE, stop_hook_active: false, last_assistant_message: 'Done.' })
})

test('each hook returns in under 200 ms (the herdr call waits for the short sh only)', async ($, on) => {
  const w = world(on)
  const t0 = Date.now()
  await $.classic.SessionStart({ ...BASE, source: 'startup' })
  await $.classic.UserPromptSubmit({ ...BASE, prompt: 'Fix the hang' })
  await $.classic.Stop({ ...BASE, stop_hook_active: false, last_assistant_message: 'Done.' })
  expect((Date.now() - t0) / 3).toBeLessThan(200)
  expect(w.calls.length).toBe(3)
})

test('the script runs herdr in the background and only inside herdr', async ($, on) => {
  const w = world(on)
  await $.classic.Stop({ ...BASE, stop_hook_active: false })
  const script = w.calls[0]!.argv[2]!
  expect(script).toContain('HERDR_ENV')
  expect(script).toMatch(/report-metadata .*&$/m)
  expect(script).toContain('$err')
})

// --- Reply style --------------------------------------------------------------------------------

const COMPOSE = { model: 'm', promptModel: 'm', surfaces: ['terminal'], tools: [], outputStyle: null, traits: [] } as never
const cmd = (command: string) => ({ command, args: '', origin: { kind: 'composer' }, presentation: { isFullscreen: false, columns: 100 } }) as never

function styleWorld(on: On) {
  on('prompt.compose', () => ({ sections: [{ id: 'intro', text: 'You are Claude.', scope: 'shared' as const }] }))
  on('prompt.submit', (_$, e) => ({ text: e.text, context: e.context }))
  on('command.register', () => ({ value: { isRegistered: true } }) as never)
}

test('the system prompt carries the Brief rule by default', async ($, on) => {
  styleWorld(on)
  const { sections } = await $.prompt.compose(COMPOSE)
  const rule = sections.find(s => s.id === 'graphite:reply-style')
  expect(rule?.text).toContain('Reply style: Brief.')
  expect(rule?.scope).toBe('session')
  expect(sections[0]?.id).toBe('intro')
})

test('the three commands are registered at session start', async ($, on) => {
  const names: string[] = []
  on('command.register', (_$, e) => { names.push(e.name); return { value: {} } as never })
  on('session.start', () => ({ cwd: '/w' }))
  await $.session.start({ cwd: '/w', surface: 'terminal' } as never)
  expect(names.sort()).toEqual(['brief', 'full', 'normal'])
})

test('/full and /normal change the style for the session; a prompt announces the switch once', async ($, on) => {
  styleWorld(on)
  await $.prompt.compose(COMPOSE) // the system prompt is built with Brief
  const first = await $.prompt.submit({ text: 'hello', wait: false, origin: { kind: 'user' } } as never)
  expect(first.context ?? []).toEqual([]) // same style as the prompt: no note

  const said = await $.command.run(cmd('full'))
  expect(said.text).toContain('Full')
  const second = await $.prompt.submit({ text: 'explain', wait: false, origin: { kind: 'user' } } as never)
  expect(second.context?.[0]).toContain('Reply style: Full.')
  const third = await $.prompt.submit({ text: 'again', wait: false, origin: { kind: 'user' } } as never)
  expect(third.context ?? []).toEqual([]) // announced once

  await $.command.run(cmd('normal'))
  const fourth = await $.prompt.submit({ text: 'x', wait: false, origin: { kind: 'user' } } as never)
  expect(fourth.context?.[0]).toContain('Reply style: Normal.')
  const composed = await $.prompt.compose(COMPOSE)
  expect(composed.sections.find(s => s.id === 'graphite:reply-style')).toBeUndefined() // Normal adds no rule
})

test('/brief after /normal brings the rule back', async ($, on) => {
  styleWorld(on)
  await $.command.run(cmd('normal'))
  await $.prompt.compose(COMPOSE)
  await $.command.run(cmd('brief'))
  const note = await $.prompt.submit({ text: 'x', wait: false, origin: { kind: 'user' } } as never)
  expect(note.context?.[0]).toContain('Reply style: Brief.')
  const { sections } = await $.prompt.compose(COMPOSE)
  expect(sections.some(s => s.id === 'graphite:reply-style')).toBe(true)
})

test('the mode shows in the feed', async ($, on) => {
  const w = world(on)
  await $.command.run(cmd('full'))
  await $.classic.Stop({ ...BASE, stop_hook_active: false })
  expect(read(w.calls.at(-1)!).tokens.mode).toBe('full')
})

test('the task tools of Claude Code make the plan (real PostToolUse shapes)', async ($, on) => {
  const w = world(on)
  const post = (tool_name: string, tool_input: unknown, tool_response: unknown) =>
    $.classic.PostToolUse({ ...BASE, tool_name, tool_input, tool_response, tool_use_id: 'x' })
  await post('TaskCreate', { subject: 'Read the form code', description: 'Read it', activeForm: 'Reading the form code' }, { task: { id: '1', subject: 'Read the form code' } })
  await post('TaskCreate', { subject: 'Fix the hang', description: 'Fix it', activeForm: 'Fixing the hang' }, { task: { id: '2', subject: 'Fix the hang' } })
  await post('TaskUpdate', { taskId: '1', status: 'in_progress' }, { success: true, taskId: '1', statusChange: { from: 'pending', to: 'in_progress' } })
  let r = read(w.calls.at(-1)!)
  expect(r.tokens).toMatchObject({ steps: 'np', step: 'Reading the form code' })
  await post('TaskUpdate', { taskId: '1', status: 'completed' }, { success: true, taskId: '1' })
  await post('TaskUpdate', { taskId: '2', status: 'in_progress' }, { success: true, taskId: '2' })
  r = read(w.calls.at(-1)!)
  expect(r.tokens).toMatchObject({ steps: 'dn', step: 'Fixing the hang' })
  const file = JSON.parse(w.calls.at(-1)!.stdin!)
  expect(file.plan.items.map((i: { name: string }) => i.name)).toEqual(['Read the form code', 'Fix the hang'])
})
