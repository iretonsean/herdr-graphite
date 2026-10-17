# Design brief

## Goal

herdr becomes a **command center for autonomous builds**. It shows what goes on. It asks you only for big design decisions or for changes that could harm the code or a machine. It does the basic work without asking you, and logs it. It stays a light desktop app. To send commands to agents while you are away, you use the Claude app with Remote Control. Everything works through the UI, not only through text commands.

## Problems with the current interface

- It looks like a terminal: monospace everywhere, hard lines and flat blocks.
- The sidebar does not tell sessions apart ("~", "claude").
- Navigation needs prefix keys that are hard to remember, and the click targets are small.
- It shows no useful information: no task, branch, limits, or what an agent needs from you.
- Chat is a wall of text, which costs tokens and attention.

## Architecture

- **herdr stays the engine.** A Graphite layer, drawn in Quickshell with the Graphite components, controls herdr through its socket API.
- **Claude Code mods** restyle the chat inside the terminal pane, and they send data to herdr with `herdr pane report-metadata`.
- **Ghostty** hosts the panes, with more padding and a softer mono font.

## Rules

1. **Calm screens.** Lots of empty space, few words, one clear thing to act on.
2. **Everything opens.** Every item in a sidebar or rail opens with details and the actions for it.
3. **Lift shows focus. Blue shows what is chosen.** Color is only for states: ok, warn and error.
4. **SF Pro for labels, SF Mono for values.** Numbers, keys, times and host names are values.
5. **Plain words.** "context used", "ready" and "Folder" replace ctx, idle and cwd. Words that developers know well stay: worktree, Remote Control, Handoff, dev server, Split right.
6. **No dollar costs.** Show the Claude limits instead: the weekly limit in the sidebar, and the session limit as a bar in the status line.
7. **Scrollbars** are invisible until you scroll. Then a thin pill shows and fades out.
8. **Roomy padding** on buttons and cards.
9. **Motion** is between subtle and expressive: a 150 ms lift, springs on switches and presses, a pulse for "working", a slow glow for "needs you".

## Decisions

| Area | Decision |
|---|---|
| Session view | Hybrid (artboard I): a rich sidebar, a calm center column, one clear action, and a Session rail |
| Sidebar cards | State, title, type label (Agent · model, GitHub CI, Deploy, Terminal), a thin bar and a time. Group by project (no project name on the card) or by state. The branch shows on hover. |
| Command center | Needs you, Running, Handled for you. It opens from the sidebar, with `alt 0`, with a global key, from a toast, and by itself after 30+ min away. |
| Chat | Brief by default: the result first, at most about 3 lines of text, plus cards. Each session has a Brief / Normal / Full switch. Questions use choices, not open text. |
| Closed sessions | One menu for every closed session from the last 7 days, opened from the sidebar, the command bar or `ctrl ⇧ t`. After a restart it opens by itself. Each working agent has two choices: "Open and wait for me" or "Open and keep working". |
| Machines | Shown by host name. Tags (x86, arm64, gpu, monitor, trackpad) and a load. If herdr is closed on a machine, it opens there first. |
| Git sync | Push local commits first, then pull or clone. Never discard changes. If two machines changed the same branch, ask. |
| Task split | Pick several machines. Claude splits the work. **Auto** picks by tags, then by load. You can move any task. |
| Claude cloud | A "machine" for basic tasks (no display, GitHub only). Its card reads the branch, PR and CI from GitHub. Roles can also run as scheduled routines. |
| Roles | Global roles with a model, a thinking level, permissions and subagents with their own models. "Delete, overwrite or reinstall" always asks. Projects assign roles to task types. Machines pick their projects. |

## What a Claude Code mod can draw in a terminal

The probe mod in `mods/genui-probe/` was tested in a real pane (Claude Code 2.1.296):

| Feature | Result |
|---|---|
| Replies as cards with a background and padding | Works |
| Rounded borders | Works |
| Chips above the prompt | Works |
| Tool calls folded to one line (ctrl+o still shows all) | Works, with a separate hook for groups of tool calls |
| Restyled question dialog | Partly: the dialog can be wrapped, but its rows cannot be replaced |
| Images | The element exists (kitty graphics). Not tested. |

## Limits we know

- **Claude cloud:** sessions start with `claude --cloud`, but there is no documented API to read their status. Cards show what GitHub shows.
- **Other machines:** they need SSH keys between them.
- **Fonts:** the terminal cannot use proportional fonts. Only the Graphite layer can.
