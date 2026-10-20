#!/usr/bin/env bash
# Installs a desktop entry "Herdr Graphite" for the Graphite app, or removes it.
# The entry runs `quickshell -p <repo>/app/shell.qml` through `setsid uwsm-app --`, so the launcher never waits for the app.
# It writes one file, <data home>/applications/herdr-graphite.desktop, and changes nothing else.
# Usage: scripts/install-app.sh [--dry-run] | --uninstall
# Test without touching your real files: XDG_DATA_HOME=$(mktemp -d) scripts/install-app.sh
set -euo pipefail
root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
data=${XDG_DATA_HOME:-$HOME/.local/share}
file=$data/applications/herdr-graphite.desktop
mode=install
case ${1:-} in
  "") ;;
  --dry-run) mode=dry ;;
  --uninstall) mode=uninstall ;;
  *) echo "usage: $0 [--dry-run] | --uninstall" >&2; exit 2 ;;
esac

if [ "$mode" = uninstall ]; then
  if [ ! -e "$file" ]; then echo "nothing to remove: $file does not exist"; exit 0; fi
  grep -q '^X-Herdr-Graphite=1$' "$file" || { echo "not removed: $file was not made by this script" >&2; exit 1; }
  rm -f "$file"
  echo "removed $file"
  exit 0
fi

[ -f "$root/app/shell.qml" ] || { echo "app/shell.qml not found in $root" >&2; exit 1; }
command -v quickshell >/dev/null || echo "note: quickshell is not in PATH; the entry will not start until it is installed" >&2
command -v uwsm-app >/dev/null || echo "note: uwsm-app is not in PATH; the entry will not start until it is installed" >&2

# Exec quoting (Desktop Entry spec): the path goes in double quotes; \ " ` $ inside are escaped with a backslash,
# and then each backslash is doubled again because the key is a string.
qml=$root/app/shell.qml
esc=$(printf '%s' "$qml" | sed -e 's/[\\"`$]/\\&/g' -e 's/\\/\\\\/g' -e 's/%/%%/g')
entry=$(cat <<DESKTOP
[Desktop Entry]
Type=Application
Name=Herdr Graphite
Comment=Sessions of your herdr agents, with a message box
Exec=setsid uwsm-app -- quickshell -p "$esc"
Icon=utilities-terminal
Terminal=false
Categories=Development;
StartupNotify=false
X-Herdr-Graphite=1
DESKTOP
)
if [ "$mode" = dry ]; then
  echo "would write $file:"; printf '%s\n' "$entry"; exit 0
fi
if [ -e "$file" ] && ! grep -q '^X-Herdr-Graphite=1$' "$file"; then
  echo "not installed: $file exists and was not made by this script (move it away first)" >&2; exit 1
fi
if [ "$(git -C "$root" rev-parse --git-dir)" != "$(git -C "$root" rev-parse --git-common-dir)" ]; then
  echo "note: $root is a git worktree. The entry breaks when the worktree is removed. Install from the main checkout." >&2
fi
mkdir -p "$(dirname "$file")"
printf '%s\n' "$entry" >"$file.tmp" && mv "$file.tmp" "$file"
echo "installed $file"
echo "start it from your launcher: Herdr Graphite. Remove it with: scripts/install-app.sh --uninstall"
