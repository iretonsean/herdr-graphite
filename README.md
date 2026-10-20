# herdr-graphite

A calmer, more graphical way to run many Claude Code agents in [herdr](https://herdr.dev), the terminal workspace manager for coding agents. It uses the Graphite theme for [Omarchy](https://omarchy.org).

**Status: a concept, with the first build step (H1, base setup) done.** This repo holds a design brief, clickable mockups, a probe mod and the base setup configs. The Graphite app is not built yet. See [docs/build-plan.md](docs/build-plan.md).

## Video

A 72-second walkthrough of the clickable mockups, with made-up data: [docs/video/herdr-graphite-concept.mp4](docs/video/herdr-graphite-concept.mp4).

## Screenshots

Rendered from the mockups with made-up data.

| | |
|---|---|
| ![Session view](docs/screenshots/I-hybrid.png) **I · Session view** | ![Command center](docs/screenshots/D-command-center.png) **D · Command center** |
| ![Start on machines](docs/screenshots/J-start-on-machines.png) **J · Start on several machines** | ![Agents and projects](docs/screenshots/K-agents-and-projects.png) **K · Agents and projects** |
| ![Closed sessions](docs/screenshots/F-closed-sessions.png) **F · Pick up after a restart** | ![Command bar](docs/screenshots/B-command-bar.png) **B · Command bar** |

## Base setup

H1 is the first build step. It changes how herdr, the terminal and Claude Code look. It needs no new app.

**What it changes**

- **herdr:** Graphite colours, no tab bar while a workspace has one tab, and distinct symbols for agent states. Your keys stay.
- **Ghostty** (replaces foot): roomy padding, the iA Writer Mono S font and Graphite colours. See [config/ghostty/](config/ghostty/README.md).
- **Claude Code:** a Graphite theme, and a status line with the model, a context bar and a bar for the 5-hour session limit. It shows no dollar costs.

| Before (foot) | After (Ghostty) |
|---|---|
| ![Before](docs/screenshots/H1-before.png) | ![After](docs/screenshots/H1-after.png) |

The session in these pictures is staged, with made-up data. `scripts/render-base-shots.sh` draws it in a headless Weston, so nothing opens on your desktop.

**Install**

```
scripts/install.sh --dry-run        # shows the plan, changes nothing
scripts/install.sh --with-ghostty   # installs Ghostty (sudo -n pacman), then applies the configs
herdr server reload-config          # applies the herdr config to the running server
```

The script copies each file that it replaces to `<file>.bak.graphite-<time>`. It edits only `theme` and `statusLine` in `~/.claude/settings.json`. To open herdr in Ghostty, see [config/ghostty/](config/ghostty/README.md). To test without touching your real files, run it with a temporary home: `HOME=$(mktemp -d) scripts/install.sh`.

**Undo**

```
scripts/uninstall.sh
```

This puts the backups back and sets the theme and the status line to their earlier values. The Ghostty package stays installed.

**Check the status line:** `scripts/test-statusline.sh` runs it with sample input.

## The idea

herdr is a strong engine, but its interface is a terminal: monospace text, hard lines, and walls of output. herdr-graphite keeps herdr as the engine and adds:

- **A command center for autonomous builds.** You see what goes on. Agents ask you only for design decisions and for changes that delete, overwrite or reinstall something. The basic work is done and logged.
- **A Graphite chrome.** A sidebar with session cards, tabs, a Session rail and a command bar. Every item opens with details and actions.
- **Calmer agent chat.** Short replies plus cards (result, plan, compare, screenshots), with the details folded until you open them.
- **Many machines.** Start agents on any online machine, or on Claude cloud for basic tasks. herdr syncs the git repos and splits the work by what each machine can do.
- **Roles.** Global agent roles with a model, a thinking level, permissions and subagents. Each project assigns roles to task types.
- **Pick up after a restart.** One Closed sessions menu reopens your sessions with their full conversations.

## What is here

| Folder | Content |
|---|---|
| [docs/design-brief.md](docs/design-brief.md) | Goals, decisions and the rules the design follows |
| [docs/build-plan.md](docs/build-plan.md) | Phases, estimates and how each phase is checked |
| [mockups/](mockups/) | The interactive mockups (artboards A–K), with made-up data |
| [mods/genui-probe/](mods/genui-probe/) | A small Claude Code mod that tests what a mod can draw in a terminal |
| [config/](config/) | herdr, Ghostty and Claude Code configs for the base setup |
| [scripts/install.sh](scripts/install.sh) | Applies the base setup. `uninstall.sh` undoes it. |
| [scripts/privacy-scan.sh](scripts/privacy-scan.sh) | Checks the repo for private data before a push |
| [scripts/render-mockups.sh](scripts/render-mockups.sh) | Renders the mockups to PNG with headless Chromium |
| [scripts/render-base-shots.sh](scripts/render-base-shots.sh) | Renders the base setup before and after pictures in headless Weston |

The mockups are `.dc.html` files made on a claude.ai Design canvas. They need that canvas to render. [mockups/README.md](mockups/README.md) describes each one.

## Privacy

All names in this repo are examples: the machines (`workstation`, `buildbox`, `laptop`) and the projects (`canvas-app`, `acme-site`, `dashboard`, `dotfiles`). Run `scripts/privacy-scan.sh` before every push. It reads your own private words from a file outside the repo.

## License

[MIT](LICENSE)
