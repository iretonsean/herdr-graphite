// The reply-style rule (Brief, Normal, Full). Plain text for the model.
// "Files:" and "Tests:" lines are a fixed form, so the Graphite app can draw them as file chips and a tests line.
import type { Mode } from '../types'

export const MODES: readonly Mode[] = ['brief', 'normal', 'full']

export const isMode = (value: unknown): value is Mode => MODES.includes(value as Mode)

const STRUCTURE = [
  'Put details in structured blocks after the prose: a list, a table, or these two lines when they apply:',
  '  Files: path/one.ts, path/two.ts',
  '  Tests: 12 passed   (or: Tests: 2 failed, 10 passed   or: Tests: not run)',
].join('\n')

export const RULES: Record<Mode, string> = {
  brief: [
    'Reply style: Brief.',
    '- Put the result in the first line.',
    '- Write at most 3 lines of prose. Do not repeat the question. Do not say what you did, unless it changes the result.',
    `- ${STRUCTURE}`,
    '- When the answer needs more room, give the result first and offer to say more.',
  ].join('\n'),
  normal: 'Reply style: Normal. Answer in the usual way for the task. Ignore any earlier instruction to reply in the Brief or Full style.',
  full: [
    'Reply style: Full.',
    '- Put the result in the first line. Then explain your reasoning and each step.',
    '- Give the reasons for your choices, and examples where they help.',
    `- ${STRUCTURE}`,
  ].join('\n'),
}

/** The note that the next prompt carries, when the session mode differs from the mode of the system prompt. */
export const switchNote = (mode: Mode): string => `[Graphite] From now on in this session: ${RULES[mode]}`

export const MODE_SAYS: Record<Mode, string> = {
  brief: 'Brief: the result first, at most 3 lines of prose, then blocks.',
  normal: 'Normal: the usual reply style.',
  full: 'Full: the result first, then the reasoning and each step.',
}

export const SECTION_ID = 'graphite:reply-style'
