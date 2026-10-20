// Graphite mods for Claude Code.
//   1. Data feed: reports the session to herdr (`herdr pane report-metadata`) and to a JSON file for the Graphite app.
//      It never blocks: each hook starts one short `sh` that runs herdr in the background, and it does nothing
//      outside herdr.
//   2. Reply style: the Brief rule in the system prompt, and /brief, /normal, /full for one session.
import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import { MODE_SAYS, SECTION_ID, RULES, isMode, switchNote } from './brief'
import {
  type FeedState, type Snapshot, type TaskBook, type Timing,
  activityFor, applyTaskCall, clearArgs, emptySnapshot, feedJson, gitFacts, isTitleSource, metadataArgs, modelName,
  planFromTodos, resultLine, shorten, stateForNotification, titleFrom, todosFromBook,
} from './feed'
import type { Mode } from '../types'

const modeAtom = atom({ plugin: 'graphite', key: 'mode' } as const, 'brief' as Mode)

// The one shell command of the feed. $1 write|clear, $2 pane, then the herdr arguments. It reads the feed JSON
// from stdin ("write"), then starts herdr in the background and returns at once, so a hook waits for no herdr call.
const SCRIPT = [
  '[ "${HERDR_ENV:-}" = 1 ] || exit 0',
  'verb=$1; pane=$2; shift 2',
  'dir=${XDG_STATE_HOME:-$HOME/.local/state}/herdr-graphite/feed',
  'file=$dir/$(printf %s "$pane" | tr -c "A-Za-z0-9._-" _).json',
  'err=/dev/null',
  'if [ "$verb" = write ]; then mkdir -p "$dir" && cat >"$file.tmp" && mv "$file.tmp" "$file"; err=$file.err; else rm -f "$file" "$file.err"; fi',
  // herdr's answer goes to a file: empty when all is well, the error text when herdr refused the report.
  '"${HERDR_BIN_PATH:-herdr}" pane report-metadata "$pane" "$@" >"$err" 2>&1 </dev/null &',
].join('\n')

/** Tool events (every call of a tool) send at most one report in this time, and only when something changed. */
const TOOL_THROTTLE_MS = 1500

// State of this session's feed. It lives in the module, so a reload starts it over (the next prompt fills it again).
const snap: Snapshot = emptySnapshot()
const timing: Timing = new Map()
const tasks: TaskBook = new Map()
const feed = {
  hostName: '',
  git: null as { cwd: string; project: string; branch: string } | null,
  lastSeq: 0,
  lastSent: 0,
  lastKey: '',
  hasTitleFromPrompt: false,
  /** The reply style that the system prompt was built with, or that the last prompt announced. */
  composed: undefined as Mode | undefined,
  fallback: 'brief' as Mode,
}

async function inHerdr($: EngineInterface): Promise<string | undefined> {
  const pane = await $.env.get('HERDR_PANE_ID')
  if (!pane || (await $.env.get('HERDR_ENV')) !== '1') return undefined
  return pane
}

function setState(state: FeedState, now: number): void {
  if (snap.state !== state) snap.since = now
  snap.state = state
}

/** Read the git facts again (the branch can change). */
async function refreshGit($: EngineInterface, cwd: string): Promise<void> {
  try {
    const r = await $.process.run(['git', '-C', cwd, 'rev-parse', '--path-format=absolute', '--git-common-dir', '--abbrev-ref', 'HEAD'], { timeoutMs: 1500 })
    feed.git = { cwd, ...gitFacts(r.exitCode === 0 ? r.stdout : '', cwd) }
  } catch {
    feed.git = { cwd, ...gitFacts('', cwd) }
  }
  snap.project = feed.git.project
  snap.branch = feed.git.branch
}

async function refreshHost($: EngineInterface): Promise<void> {
  if (feed.hostName !== '') return
  try {
    feed.hostName = (await $.process.run(['hostname'], { timeoutMs: 1000 })).stdout.trim()
  } catch { /* the card shows no machine */ }
  snap.machine = feed.hostName
}

async function refreshUsage($: EngineInterface): Promise<void> {
  try {
    const u = await $.session.usage()
    snap.context = u.context.percent ?? snap.context
    const five = u.rateLimits.find(r => r.kind === 'five_hour')
    const week = u.rateLimits.find(r => r.kind === 'seven_day')
    if (five) {
      snap.limit = five.percentUsed
      const at = five.resetsAt === undefined ? NaN : Date.parse(five.resetsAt)
      snap.limitReset = Number.isNaN(at) ? null : at
    }
    if (week) snap.weekly = week.percentUsed
  } catch { /* keep the last figures */ }
}

/** Send the whole snapshot. Never throws, and waits only for the short `sh`. */
async function report(
  $: EngineInterface, pane: string, e: { session_id: string; cwd: string }, now: number, verb: 'write' | 'clear' = 'write',
): Promise<void> {
  try {
    snap.mode = (await read($, modeAtom)) ?? feed.fallback
    feed.lastSeq = Math.max(now, feed.lastSeq + 1)
    const args = verb === 'write' ? metadataArgs(snap, feed.lastSeq) : clearArgs(feed.lastSeq)
    await $.process.run(['sh', '-c', SCRIPT, 'sh', verb, pane, ...args], {
      stdin: verb === 'write' ? feedJson(snap, pane, e.session_id, e.cwd, now) : '',
      timeoutMs: 1000,
    })
    feed.lastSent = now
    feed.lastKey = JSON.stringify(args.slice(4))
  } catch { /* a feed that fails must not disturb the session */ }
}

export const register: Register = (on, options) => {
  feed.fallback = isMode(options?.defaultMode) ? options.defaultMode : 'brief'

  // --- Data feed ---------------------------------------------------------------------------------

  on('classic.SessionStart', async ($, e, next) => {
    const pane = await inHerdr($)
    if (pane) {
      const now = await $.clock.now()
      if (e.source !== 'compact') {
        snap.started = now
        setState('ready', now)
        snap.activity = ''
        snap.ask = ''
      }
      snap.model = modelName(e.model) || snap.model
      if (e.session_title) snap.title = shorten(e.session_title, 60)
      await Promise.all([refreshHost($), refreshGit($, e.cwd), refreshUsage($)])
      await report($, pane, e, now)
    }
    return next(e)
  })

  on('classic.UserPromptSubmit', async ($, e, next) => {
    const pane = await inHerdr($)
    if (pane) {
      const now = await $.clock.now()
      if (e.session_title) snap.title = shorten(e.session_title, 60)
      else if (!feed.hasTitleFromPrompt && isTitleSource(e.prompt, e.source)) {
        snap.title = titleFrom(e.prompt)
        feed.hasTitleFromPrompt = true
      }
      setState('working', now)
      snap.activity = ''
      snap.ask = ''
      await Promise.all([refreshHost($), refreshGit($, e.cwd), refreshUsage($)])
      await report($, pane, e, now)
    }
    return next(e)
  })

  // PreToolUse: light. At most one report per throttle time, and only if the picture changed.
  on('tool.call', async ($, e, next) => {
    const pane = await inHerdr($)
    if (pane) {
      const now = await $.clock.now()
      snap.activity = activityFor(String(e.tool), e)
      if (snap.state === 'needs' || snap.state === 'ready' || snap.state === 'done') setState('working', now)
      const changed = JSON.stringify(metadataArgs(snap, 0).slice(4)) !== feed.lastKey
      if (changed && now - feed.lastSent >= TOOL_THROTTLE_MS) {
        await refreshHost($)
        await report($, pane, { session_id: '', cwd: feed.git?.cwd ?? '' }, now)
      }
    }
    return next(e)
  })

  on('classic.PostToolUse', async ($, e, next) => {
    const pane = await inHerdr($)
    if (pane) {
      const now = await $.clock.now()
      let isPlan = false
      if (e.tool_name === 'TodoWrite') {
        snap.plan = planFromTodos(e.tool_input, timing, now)
        isPlan = true
      } else if (e.tool_name === 'TaskCreate' || e.tool_name === 'TaskUpdate') {
        applyTaskCall(tasks, e.tool_name, e.tool_input, e.tool_response)
        snap.plan = planFromTodos(todosFromBook(tasks), timing, now)
        isPlan = true
      }
      if (snap.state === 'needs') setState('working', now)
      const changed = JSON.stringify(metadataArgs(snap, 0).slice(4)) !== feed.lastKey
      // A plan change goes out at once; other tool news waits for the throttle.
      if (changed && (isPlan || now - feed.lastSent >= TOOL_THROTTLE_MS)) {
        await refreshUsage($)
        await report($, pane, e, now)
      }
    }
    return next(e)
  })

  on('classic.Notification', async ($, e, next) => {
    const pane = await inHerdr($)
    if (pane) {
      const now = await $.clock.now()
      setState(stateForNotification(e.notification_type), now)
      snap.ask = e.notification_type === 'idle_prompt' ? '' : e.message
      snap.activity = ''
      await report($, pane, e, now)
    }
    return next(e)
  })

  on('classic.Stop', async ($, e, next) => {
    const pane = await inHerdr($)
    if (pane) {
      const now = await $.clock.now()
      setState('done', now)
      snap.activity = ''
      snap.ask = ''
      if (e.last_assistant_message) snap.last = resultLine(e.last_assistant_message)
      await Promise.all([refreshGit($, e.cwd), refreshUsage($)])
      await report($, pane, e, now)
    }
    return next(e)
  })

  on('classic.StopFailure', async ($, e, next) => {
    const pane = await inHerdr($)
    if (pane) {
      const now = await $.clock.now()
      setState('failed', now)
      snap.activity = ''
      snap.last = e.last_assistant_message ? resultLine(e.last_assistant_message) : shorten(`Stopped: ${e.error_details ?? e.error}`)
      await refreshUsage($)
      await report($, pane, e, now)
    }
    return next(e)
  })

  on('classic.SessionEnd', async ($, e, next) => {
    const pane = await inHerdr($)
    if (pane) await report($, pane, e, await $.clock.now(), 'clear')
    return next(e)
  })

  // --- Reply style -------------------------------------------------------------------------------

  on('session.start', async ($, e, next) => {
    for (const name of ['brief', 'normal', 'full'] as const) {
      await $.command.register({ name, description: `Reply style for this session: ${MODE_SAYS[name]}` })
    }
    return next(e)
  })

  for (const name of ['brief', 'normal', 'full'] as const) {
    on('command.run', { command: name }, async $ => {
      await update($, modeAtom, () => name)
      return { text: `Reply style set to ${MODE_SAYS[name]} It applies from your next prompt.` }
    })
  }

  // The system prompt carries the rule for the mode that the session has when it is built.
  on('prompt.compose', async ($, e, next) => {
    const result = await next(e)
    const mode = (await read($, modeAtom)) ?? feed.fallback
    feed.composed = mode
    if (mode === 'normal') return result
    return { sections: [...result.sections, { id: SECTION_ID, text: RULES[mode], scope: 'session' as const }] }
  })

  // A switch in the middle of a session reaches the model as a note with the next prompt. The system prompt
  // may stay as it was built, because a changed prompt would spend the prompt cache.
  on('prompt.submit', async ($, e, next) => {
    const mode = (await read($, modeAtom)) ?? feed.fallback
    if (mode === (feed.composed ?? feed.fallback)) return next(e)
    feed.composed = mode
    return next({ ...e, context: [...(e.context ?? []), switchNote(mode)] })
  })
}
