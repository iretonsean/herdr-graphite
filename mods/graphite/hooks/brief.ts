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

// Written for the model, in short plain sentences. The Brief rule is for chat replies only: work products and
// reports that were asked for are written in full, because an autonomous session has nobody to answer an offer.
const IN_FULL = [
  'Files, documents, reports, briefs, handoffs, reviews, commit messages and pull request text are written in full, in the form they need. This rule does not shorten them.',
  'When the user, a brief or a skill asks for a full report or for a fixed report form, give it in full. That request comes before this rule.',
].join('\n')

export const RULES: Record<Mode, string> = {
  brief: [
    'Reply style: Brief. It is for chat replies only.',
    `- ${IN_FULL.split('\n').join('\n- ')}`,
    '- In a chat reply, put the result in the first line.',
    '- In a chat reply, write at most 3 lines of prose. Do not repeat the question. Do not say what you did, unless it changes the result.',
    `- ${STRUCTURE}`,
    '- Put everything else that the person needs in structured blocks after the result. Do not end with an offer to say more: nobody may be there to answer.',
  ].join('\n'),
  normal: 'Reply style: Normal. Answer in the usual way for the task. Ignore any earlier instruction to reply in the Brief or Full style.',
  full: [
    'Reply style: Full.',
    '- Put the result in the first line. Then explain your reasoning and each step.',
    '- Give the reasons for your choices, and examples where they help.',
    `- ${STRUCTURE}`,
    `- ${IN_FULL.split('\n').join('\n- ')}`,
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
