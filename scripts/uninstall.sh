#!/usr/bin/env bash
# Undoes scripts/install.sh with its manifest: puts each backed-up file back, removes each file that the install
# created, and sets the Claude Code theme and status line in settings.json back to their earlier values.
#   scripts/uninstall.sh [--dry-run] [MANIFEST]     (default: the newest manifest)
# Other keys in settings.json stay as they are now. A file that changed after the install is still restored from its
# backup; the changed copy is kept as <file>.after-graphite-<timestamp>.
set -euo pipefail

dry=0 manifest=
for a in "$@"; do
  case $a in
    --dry-run) dry=1 ;;
    -h|--help) sed -n 2,7p "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "unknown option: $a" >&2; exit 2 ;;
    *) manifest=$a ;;
  esac
done
command -v jq >/dev/null || { echo "uninstall: jq is required" >&2; exit 1; }
state=$HOME/.local/state/herdr-graphite
[ -n "$manifest" ] || manifest=$(ls -1 "$state"/install-*.json 2>/dev/null | sort | tail -1 || true)
[ -n "$manifest" ] && [ -f "$manifest" ] || { echo "uninstall: no manifest in $state" >&2; exit 1; }
jq -e . "$manifest" >/dev/null || { echo "uninstall: $manifest is not valid JSON" >&2; exit 1; }

stamp=$(date +%Y%m%d-%H%M%S)
say() { if [ $dry = 1 ]; then echo "[dry-run] $*"; else echo "$*"; fi; }
run() { [ $dry = 1 ] || "$@"; }
echo "herdr-graphite uninstall: $manifest"

while IFS=$'\t' read -r target backup; do
  [ -n "$target" ] || continue
  if [ "$backup" = - ]; then
    say "remove: $target (the install created it)"
    run rm -f "$target"
  elif [ -e "$backup" ]; then
    say "restore: $backup -> $target"
    if [ -e "$target" ] && [ "$dry" = 0 ]; then cp -a "$target" "$target.after-graphite-$stamp"; fi
    run mv -f "$backup" "$target"
  else
    echo "warning: backup $backup is missing; $target left as it is" >&2
  fi
done < <(jq -r '.files[] | [.target, .backup] | @tsv' "$manifest")

settings=$(jq -r '.settings.path' "$manifest")
if [ "$(jq -r '.settings.changed' "$manifest")" = true ] && [ -f "$settings" ]; then
  say "edit: $settings (theme and statusLine back to the earlier values)"
  if [ $dry = 0 ]; then
    tmp=$(mktemp "$settings.XXXXXX")
    jq --argjson t "$(jq -c '.settings.prev_theme' "$manifest")" --argjson s "$(jq -c '.settings.prev_statusLine' "$manifest")" '
      (if $t == null then del(.theme) else .theme = $t end) | (if $s == null then del(.statusLine) else .statusLine = $s end)' \
      "$settings" >"$tmp"
    chmod --reference="$settings" "$tmp"; mv "$tmp" "$settings"
    sb=$(jq -r '.settings.backup' "$manifest")
    [ "$sb" = - ] || echo "note: the full backup of the old settings is still at $sb"
  fi
fi

term=$(jq -r '.default_terminal_before' "$manifest")
if [ "$term" != - ] && [ -n "$term" ]; then
  say "default terminal back to: $term (omarchy-default-terminal $term)"
  run omarchy-default-terminal "$term"
fi

run mv -f "$manifest" "$manifest.undone"
say "done. The Ghostty package stays installed; remove it yourself with: sudo pacman -Rns ghostty"
echo "Apply to a running herdr with: herdr server reload-config"
