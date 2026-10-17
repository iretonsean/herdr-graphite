# Build plan

**Status: waiting for approval.** Nothing in this plan has started.

## Summary

There are 7 phases. Each phase is one item (H0–H6) with one build, one Opus review and one fix round. A phase is done when its check passes on the real machine.

- **Total:** about **13–20 M fresh tokens**. With the current usage rates, that is about 35–55 % of one weekly Claude limit, and 4–6 five-hour session windows.
- **Calendar time:** about 5–8 days, plus your reviews.
- **The least certain phases** are H3 and H5. No earlier work of this type exists to calibrate them.

## Before H3: one decision

**D1. Who draws the session view?**
- **(a) The Graphite layer** draws the calm view (artboard I) from the session data. The real terminal sits behind a toggle.
- **(b) Claude Code mods** draw cards, rounded borders and folded steps inside the terminal. The Graphite layer only adds the sidebar, the rail and the command bar.

Option (b) is lighter and keeps Claude Code's own features. Option (a) looks closer to the mockups (SF Pro, motion). **Recommendation:** first (b), in H2, then add (a) later only for the parts that need it.

## Phases

| Item | Phase | What changes | Check | Fresh tokens |
|---|---|---|---|---|
| H0 | Repo and privacy | This repo, demo data, `scripts/privacy-scan.sh` as a pre-push hook | the scan passes; no private word in the history | 0.2–0.3 M |
| H1 | Base setup | herdr config (Graphite colors, no tab bar, symbols), Ghostty with padding and the font, Claude Code theme and status line (model, context bar, session limit bar) | screenshots of a real session, before and after | 0.3–0.5 M |
| H2 | Claude Code mods | Brief rule, reply cards, folded tool calls with ctrl+o, chips above the prompt, a wrapper with a "recommended" tag for the question dialog, hooks that send title, state, context and limits to herdr | `claude plugin validate` and `claude plugin test` pass; a capture of a real pane | 2.5–3.5 M |
| H3 | Graphite chrome | A Quickshell sidebar (cards that open, grouping, closed sessions row), tabs, the Session rail, the command bar, toasts, a herdr socket API client | each artboard I part works on the real desktop; no blocking calls in Hyprland binds | 4–6 M |
| H4 | Command center and restore | The command center (needs you, running, handled), the welcome back banner, the Closed sessions menu, restore after a reboot (herdr's Claude integration) | a reboot test: sessions come back with their conversations | 2–3 M |
| H5 | Many machines and roles | SSH keys between the machines, `herdr --remote`, git sync with conflict choices, task split with Auto, the Roles, Projects and Machines settings | a session starts on a second machine where herdr was closed; a conflict asks | 3–4.5 M |
| H6 | Claude cloud | Basic tasks go to `claude --cloud`; cards follow the branch, PR and CI on GitHub; routines start from roles | a basic task runs in the cloud and its PR shows on the card | 1–1.5 M |

The table does not include the reviews and fix rounds. They add about 20 %.

## How to work

- **Tag every session** with `ITEM: H<n>` and `ROLE: build|review|fix|lead`, so the token ledger records each phase. The next estimate then uses real numbers.
- **One review and one fix round per phase.** The lead merges only when CI is green.
- **Ask only** for design decisions and for destructive changes.
- **Before every push:** run `scripts/privacy-scan.sh`, and check each screenshot by hand. Crop it to the element. It must show no networks, devices, IP addresses, private projects or accounts.
