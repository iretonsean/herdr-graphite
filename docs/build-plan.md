# Build plan

**Status: approved on 2026-10-16. The build starts in the week of 2026-10-19.** Nothing has started yet.

## Summary

There are 7 phases. Each phase is one item (H0–H6) with one build, one Opus review and one fix round. A phase is done when its check passes on the real machine.

- **Total:** about **17–26 M fresh tokens**. With the current usage rates, that is about 45–70 % of one weekly Claude limit, and 5–8 five-hour session windows.
- **Calendar time:** about 7–10 days, plus your reviews.
- **The least certain phases** are H3 and H5. No earlier work of this type exists to calibrate them.

## Decision D1: the Graphite layer draws the session view

**Decided:** the Graphite layer draws the calm view (artboard I). This is a new front-end app on herdr, not a reskin.

- **herdr stays the engine:** the terminals, the panes, agent states, saving and restoring the session, `--remote`, and the socket API.
- **The app** draws each turn from Claude Code's session files and from the data that the hooks send.
  - Your messages go to the agent with `herdr agent prompt`.
  - When you click a choice, the app sends the key presses to the agent's question dialog.
- **Show terminal** brings forward the Ghostty window with herdr, zoomed to that pane. Quickshell cannot embed a terminal.
- **Risk:** the session file format has no documentation and can change. The app reads only a few fields. When it cannot read a file, it falls back to the terminal view.

## Phases

| Item | Phase | What changes | Check | Fresh tokens |
|---|---|---|---|---|
| H0 | Repo and privacy | This repo, demo data, `scripts/privacy-scan.sh` as a pre-push hook | the scan passes; no private word in the history | 0.2–0.3 M |
| H1 | Base setup | herdr config (Graphite colors, no tab bar, symbols), Ghostty with padding and the font, Claude Code theme and status line (model, context bar, session limit bar) | screenshots of a real session, before and after | 0.3–0.5 M |
| H2 | Claude Code mods and data feed | Brief rule, AskUserQuestion rule, hooks that send title, state, plan, context and limits to herdr; terminal cards and folded tool calls for the times the real terminal is open | `claude plugin validate` and `claude plugin test` pass; herdr shows the reported metadata | 2–3 M |
| H3 | Graphite app | A Quickshell app with a herdr socket API client: the sidebar (cards that open, grouping, closed sessions row), tabs, the session view (turns from the session files: result cards, folded steps, choices that answer the dialog, the message box), the Session rail, the command bar, toasts, Show terminal | each artboard I part works on the real desktop with a live session; no blocking calls in Hyprland binds; a session whose file it cannot read falls back to the terminal | 8–11 M |
| H4 | Command center and restore | The command center (needs you, running, handled), the welcome back banner, the Closed sessions menu, restore after a reboot (herdr's Claude integration) | a reboot test: sessions come back with their conversations | 2–3 M |
| H5 | Many machines and roles | SSH keys between the machines, `herdr --remote`, git sync with conflict choices, task split with Auto, the Roles, Projects and Machines settings | a session starts on a second machine where herdr was closed; a conflict asks | 3–4.5 M |
| H6 | Claude cloud | Basic tasks go to `claude --cloud`; cards follow the branch, PR and CI on GitHub; routines start from roles | a basic task runs in the cloud and its PR shows on the card | 1–1.5 M |

The table does not include the reviews and fix rounds. They add about 20 %.

## How to work

- **Tag every session** with `ITEM: H<n>` and `ROLE: build|review|fix|lead`, so the token ledger records each phase. The next estimate then uses real numbers.
- **One review and one fix round per phase.** The lead merges only when CI is green.
- **Ask only** for design decisions and for destructive changes.
- **Before every push:** run `scripts/privacy-scan.sh`, and check each screenshot by hand. Crop it to the element. It must show no networks, devices, IP addresses, private projects or accounts.
