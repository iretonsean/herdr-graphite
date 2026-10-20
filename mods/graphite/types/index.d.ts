// The state that the graphite mod keeps for one session. The host holds it, so a reload keeps it.
export type Mode = 'brief' | 'normal' | 'full'

declare module 'claude-code' {
  interface PluginState {
    graphite: { mode: Mode }
  }
}
