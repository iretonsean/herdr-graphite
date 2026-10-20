#!/usr/bin/env bash
# Installs the herdr-graphite base setup (H1): herdr config, Ghostty config, Claude Code theme and status line.
#   scripts/install.sh [--dry-run] [--with-ghostty] [--set-default-terminal]
#
#   --dry-run               Show the plan. Change nothing.
#   --with-ghostty          Install the Ghostty package first: sudo -n pacman -S --needed --noconfirm ghostty.
#                           "sudo -n" never asks for a password; it fails when sudo needs one.
#   --set-default-terminal  Run omarchy-default-terminal ghostty, so the Omarchy herdr launcher opens Ghostty.
#                           It needs Ghostty (installed, or --with-ghostty). It shows a desktop notification.
#                           It backs up ~/.config/xdg-terminals.list first; uninstall restores that file.
#                           Without it, use the launch line in config/ghostty/README.md.
#
# Every file that this script replaces is first copied to <file>.bak.graphite-<timestamp>-<NN>.<NN>. A manifest in
# ~/.local/state/herdr-graphite/ records what changed. scripts/uninstall.sh reads it.
# To test without touching your real config: HOME=$(mktemp -d) scripts/install.sh
set -euo pipefail

dry=0 with_ghostty=0 set_term=0
for a in "$@"; do
  case $a in
    --dry-run) dry=1 ;;
    --with-ghostty) with_ghostty=1 ;;
    --set-default-terminal) set_term=1 ;;
    -h|--help) sed -n 2,16p "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

root=$(cd "$(dirname "$0")/.." && pwd)
stamp=$(date +%Y%m%d-%H%M%S)
state=$HOME/.local/state/herdr-graphite
n=1; while compgen -G "$state/install-$stamp-$(printf %02d $n).json*" >/dev/null; do n=$((n + 1)); done
tag=$stamp-$(printf %02d $n) # -NN keeps the names unique and in order when two installs share a second
manifest=$state/install-$tag.json
settings=$HOME/.claude/settings.json
statusline_cmd=$HOME/.claude/graphite-statusline.sh

# source -> target -> mode
files=(
  "$root/config/herdr/config.toml|$HOME/.config/herdr/config.toml|644"
  "$root/config/ghostty/config|$HOME/.config/ghostty/config|644"
  "$root/config/claude/graphite.json|$HOME/.claude/themes/graphite.json|644"
  "$root/config/claude/statusline.sh|$statusline_cmd|755"
)

command -v jq >/dev/null || { echo "install: jq is required" >&2; exit 1; }
for f in "${files[@]}"; do [ -f "${f%%|*}" ] || { echo "install: missing ${f%%|*}" >&2; exit 1; }; done
if [ -f "$settings" ]; then jq -e . "$settings" >/dev/null || { echo "install: $settings is not valid JSON; nothing changed" >&2; exit 1; }; fi

if [ $set_term = 1 ] && [ $with_ghostty = 0 ] && ! command -v ghostty >/dev/null; then
  echo "install: --set-default-terminal needs Ghostty. Install it first, or add --with-ghostty. Nothing changed." >&2
  exit 1
fi

say() { if [ $dry = 1 ]; then echo "[dry-run] $*"; else echo "$*"; fi; }
run() { [ $dry = 1 ] || "$@"; }

echo "herdr-graphite base setup: $([ $dry = 1 ] && echo plan || echo install) (HOME=$HOME)"

if [ $with_ghostty = 1 ]; then
  if pacman -Q ghostty >/dev/null 2>&1; then say "ghostty: already installed"
  else
    say "install package: sudo -n pacman -S --needed --noconfirm ghostty"
    run sudo -n pacman -S --needed --noconfirm ghostty
  fi
fi

run mkdir -p "$state"
entries=()
for f in "${files[@]}"; do
  IFS='|' read -r src dst mode <<<"$f"
  backup=-
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    if cmp -s "$src" "$dst"; then say "unchanged: $dst"; continue; fi
    backup=$dst.bak.graphite-$tag
    say "back up: $dst -> $backup"
    run cp -a "$dst" "$backup"
  fi
  say "write: $dst"
  run mkdir -p "$(dirname "$dst")"
  run install -m "$mode" "$src" "$dst"
  sha=-; [ $dry = 1 ] || sha=$(sha256sum "$dst" | cut -d' ' -f1)
  entries+=("$(jq -n --arg t "$dst" --arg b "$backup" --arg h "$sha" '{target:$t, backup:$b, installed_sha256:$h}')")
done

# ~/.claude/settings.json: set the theme and the status line. Only these two keys change.
prev_theme=null prev_status=null settings_backup=-
if [ -f "$settings" ]; then
  prev_theme=$(jq -c '.theme // null' "$settings"); prev_status=$(jq -c '.statusLine // null' "$settings")
fi
want_status=$(jq -nc --arg c "$statusline_cmd" '{type:"command", command:$c, padding:0}')
if [ -f "$settings" ] && [ "$(jq -c '[.theme, .statusLine]' "$settings")" = "$(jq -nc --argjson s "$want_status" '["custom:graphite", $s]')" ]; then
  say "unchanged: $settings"
  settings_done=0
else
  if [ -f "$settings" ]; then
    settings_backup=$settings.bak.graphite-$tag
    say "back up: $settings -> $settings_backup"
    run cp -a "$settings" "$settings_backup"
  fi
  say "edit: $settings (theme: custom:graphite, statusLine: $statusline_cmd)"
  if [ $dry = 0 ]; then
    mkdir -p "$(dirname "$settings")"
    [ -f "$settings" ] || echo '{}' >"$settings"
    tmp=$(mktemp "$settings.XXXXXX")
    jq --argjson s "$want_status" '.theme = "custom:graphite" | .statusLine = $s' "$settings" >"$tmp"
    chmod --reference="$settings" "$tmp"; mv "$tmp" "$settings"
  fi
  settings_done=1
fi

if [ $set_term = 1 ]; then
  xt=$HOME/.config/xdg-terminals.list # the file that omarchy-default-terminal writes
  backup=-
  if [ -e "$xt" ] || [ -L "$xt" ]; then
    backup=$xt.bak.graphite-$tag
    say "back up: $xt -> $backup"
    run cp -a "$xt" "$backup"
  fi
  say "default terminal: ghostty (omarchy-default-terminal ghostty writes $xt)"
  run omarchy-default-terminal ghostty
  if [ $dry = 0 ]; then
    if [ "$backup" != - ] && cmp -s "$backup" "$xt"; then
      rm -f "$backup"; say "unchanged: $xt"
    else
      entries+=("$(jq -n --arg t "$xt" --arg b "$backup" --arg h "$(sha256sum "$xt" | cut -d' ' -f1)" '{target:$t, backup:$b, installed_sha256:$h}')")
    fi
  fi
fi

if [ $dry = 0 ] && [ -z "${entries[*]:-}" ] && [ "${settings_done:-0}" = 0 ]; then
  echo "nothing changed; no manifest written"
elif [ $dry = 0 ]; then
  ssha=-; [ "${settings_done:-0}" = 1 ] && ssha=$(sha256sum "$settings" | cut -d' ' -f1)
  jq -n --arg ssha "$ssha" --arg stamp "$tag" --arg home "$HOME" --arg settings "$settings" --arg sb "$settings_backup" \
    --argjson pt "$prev_theme" --argjson ps "$prev_status" --argjson sd "${settings_done:-0}" \
    --argjson files "$(printf '%s\n' "${entries[@]:-}" | jq -s 'map(select(. != null))')" \
    '{stamp:$stamp, home:$home, files:$files,
      settings:{path:$settings, backup:$sb, changed:($sd == 1), installed_sha256:$ssha, prev_theme:$pt, prev_statusLine:$ps}}' >"$manifest"
  echo "manifest: $manifest"
fi

cat <<MSG

Next steps (not done by this script):
  - herdr: apply the new config in the running server with: herdr server reload-config
  - Ghostty: launch herdr in it with the line in config/ghostty/README.md, or run this script with
    --set-default-terminal.
  - Claude Code: the theme and status line load in new sessions; /theme shows "Graphite".
  - Undo: scripts/uninstall.sh
MSG
