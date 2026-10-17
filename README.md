# herdr-graphite

A calmer, more graphical way to run many Claude Code agents in [herdr](https://herdr.dev), the terminal workspace manager for coding agents. It uses the Graphite theme for [Omarchy](https://omarchy.org).

**Status: design phase.** This repo holds the design brief, the mockups and a probe mod. Nothing is built yet. See [docs/build-plan.md](docs/build-plan.md).

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
| [scripts/privacy-scan.sh](scripts/privacy-scan.sh) | Checks the repo for private data before a push |

The mockups are `.dc.html` files made on a claude.ai Design canvas. They need that canvas to render. [mockups/README.md](mockups/README.md) describes each one.

## Privacy

All names in this repo are examples: the machines (`workstation`, `buildbox`, `laptop`) and the projects (`canvas-app`, `acme-site`, `dashboard`, `dotfiles`). Run `scripts/privacy-scan.sh` before every push. It reads your own private words from a file outside the repo.

## License

[MIT](LICENSE)
