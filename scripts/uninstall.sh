#!/usr/bin/env bash
# Undoes scripts/install.sh with its manifest: puts each backed-up file back, removes each file that the install
# created, and sets the Claude Code theme and status line in settings.json back to their earlier values.
#   scripts/uninstall.sh [--dry-run] [MANIFEST]     (default: the newest manifest)
# It undoes only ONE install: the newest, or the manifest that you name. After two installs that changed different
# files, run it twice (each run renames the manifest that it used to *.undone).
# Other keys in settings.json stay as they are now. A file that changed after the install is still restored from its
# backup; the changed copy is kept as <file>.after-graphite-<timestamp>. A file that did not change is not copied.
set -euo pipefail

dry=0 manifest=
for a in "$@"; do
  case $a in
    --dry-run) dry=1 ;;
    -h|--help) sed -n 2,10p "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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

while IFS=$'\x1f' read -r target backup sha; do
  [ -n "$target" ] || continue
  if [ "$backup" = - ]; then
    say "remove: $target (the install created it)"
    run rm -f "$target"
  elif [ -e "$backup" ]; then
    say "restore: $backup -> $target"
    # Keep the current file only when it is not the one that the install wrote.
    if [ -e "$target" ] && { [ "$sha" = - ] || [ "$(sha256sum "$target" | cut -d' ' -f1)" != "$sha" ]; }; then
      say "keep: $target changed after the install; copy kept as $target.after-graphite-$stamp"
      run cp -a "$target" "$target.after-graphite-$stamp"
    fi
    run mv -f "$backup" "$target"
  else
    echo "warning: backup $backup is missing; $target left as it is" >&2
  fi
done < <(jq -r '.files[] | [.target, .backup, (.installed_sha256 // "-")] | join("\u001f")' "$manifest")

settings=$(jq -r '.settings.path' "$manifest")
if [ "$(jq -r '.settings.changed' "$manifest")" = true ] && [ -f "$settings" ]; then
  sb=$(jq -r '.settings.backup' "$manifest"); ssha=$(jq -r '.settings.installed_sha256 // "-"' "$manifest")
  if [ "$sb" != - ] && [ -f "$sb" ] && [ "$ssha" != - ] && [ "$(sha256sum "$settings" | cut -d' ' -f1)" = "$ssha" ]; then
    # Nothing else touched settings.json since the install: put the backup back, byte for byte.
    say "restore: $sb -> $settings"
    run mv -f "$sb" "$settings"
  else
    say "edit: $settings (theme and statusLine back to the earlier values; the file changed since the install)"
    if [ $dry = 0 ]; then
      tmp=$(mktemp "$settings.XXXXXX")
      jq --argjson t "$(jq -c '.settings.prev_theme' "$manifest")" --argjson s "$(jq -c '.settings.prev_statusLine' "$manifest")" '
        (if $t == null then del(.theme) else .theme = $t end) | (if $s == null then del(.statusLine) else .statusLine = $s end)' \
        "$settings" >"$tmp"
      chmod --reference="$settings" "$tmp"; mv "$tmp" "$settings"
      [ "$sb" = - ] || echo "note: the full backup of the old settings is still at $sb"
    fi
  fi
fi

run mv -f "$manifest" "$manifest.undone"
say "done. The Ghostty package stays installed; remove it yourself with: sudo pacman -Rns ghostty"
echo "Apply to a running herdr with: herdr server reload-config"
