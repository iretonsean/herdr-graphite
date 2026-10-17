import type { Register } from 'claude-code'

const BG = '#1b1b1e'

export const register: Register = on => {
  // a. AssistantMessage as a card
  on('ui.render', { component: 'AssistantMessage' }, ($, e, next) => {
    const { Box, Text } = $.ui.resolve(e)
    const lines = e.props.text.split('\n').filter(l => l.trim())
    const first = lines[0] ?? ''
    const more = lines.length > 1 || first.length > 80
    return (
      <Box backgroundColor={BG} paddingX={2} paddingY={1} flexDirection="column" width="100%">
        <Text bold color="#7aa2f7" backgroundColor={BG}>Claude</Text>
        <Text backgroundColor={BG}>{first.slice(0, 80)}{more ? ' ... more' : ''}</Text>
      </Box>
    )
  })

  // b. ToolUse as one dim line; hide the result row
  on('ui.render', { component: 'ToolUse' }, ($, e, next) => {
    const { Text } = $.ui.resolve(e)
    const inp = (e.props.input ?? {}) as Record<string, unknown>
    const target = String(inp.file_path ?? inp.command ?? inp.pattern ?? '').split('/').pop()
    return <Text dimColor>▸ {e.props.tool} {target}{e.props.isRunning ? ' ...' : ''}</Text>
  })
  on('ui.render', { component: 'ToolResult' }, ($, e, next) => {
    const { Text } = $.ui.resolve(e)
    return <Text dimColor>  (result folded)</Text>
  })

  // c. AskUserQuestion: wrap the engine's own dialog node
  on('ui.render', { component: 'AskUserQuestion' }, async ($, e, next) => {
    const { Box, Text } = $.ui.resolve(e)
    const engine = await next(e)
    return (
      <Box flexDirection="column" borderStyle="round" borderColor="#7aa2f7" paddingX={1}>
        <Text backgroundColor="#1f6f3a" color="#ffffff"> recommended: 1 </Text>
        {engine}
      </Box>
    )
  })

  on('ui.render', { component: 'ToolGroup' }, ($, e, next) => {
    if (e.props.isExpanded) return next(e)
    const { Text } = $.ui.resolve(e)
    return <Text dimColor>▸ {e.props.calls.length} tool calls (group)</Text>
  })

  // d. band with chips
  on('ui.render', { component: 'AbovePrompt' }, ($, e, next) => {
    if (e.props.hasSurvey) return next(e)
    const { Box, Text } = $.ui.resolve(e)
    return (
      <Box gap={1} borderStyle="round" borderColor="#888888" paddingX={1}>
        <Text backgroundColor="#3b3b5c" color="#ffffff"> sonnet </Text>
        <Text backgroundColor="#1f6f3a" color="#ffffff"> ctx 12% </Text>
        <Text backgroundColor="#7a4a1f" color="#ffffff"> {e.props.isWorking ? 'working' : 'idle'} </Text>
      </Box>
    )
  })

  // e. round border on a Box in the band: separate hook would conflict; AskUserQuestion box above uses it.
}
