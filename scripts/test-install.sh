#!/usr/bin/env bash
# Tests scripts/install.sh and scripts/uninstall.sh in a temporary HOME. Nothing outside the temp folder changes:
# omarchy-default-terminal and ghostty are fakes in a temp bin folder at the front of PATH.
# Usage: scripts/test-install.sh
set -u
root=$(git rev-parse --show-toplevel)
work=$(mktemp -d "${TMPDIR:-/tmp}/herdr-graphite-test.XXXXXX")
trap 'rm -rf "$work"' EXIT
fail=0
ok()   { echo "ok   $1"; }
bad()  { echo "FAIL $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1  [$2]"; fi; }

fakebin=$work/bin; mkdir -p "$fakebin"
# A fake omarchy-default-terminal: writes the terminals list like the real one and logs each call.
cat >"$fakebin/omarchy-default-terminal" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >>"$FAKE_LOG"
[ "${1:-}" = ghostty ] || exit 1
printf '# Terminal emulator preference order for xdg-terminal-exec\ncom.mitchellh.ghostty.desktop\n' >"$HOME/.config/xdg-terminals.list"
FAKE
printf '#!/bin/sh\nexit 0\n' >"$fakebin/ghostty"
chmod +x "$fakebin"/*

new_home() { # new_home NAME -> sets and exports HOME (not in a subshell!) to a new folder with seed files (made-up content)
  h=$work/$1; rm -rf "$h"
  mkdir -p "$h/.config/herdr" "$h/.config/ghostty" "$h/.claude"
  echo 'seed herdr config' >"$h/.config/herdr/config.toml"
  echo 'seed ghostty config' >"$h/.config/ghostty/config"
  echo '{"theme":"dark","env":{"A":"1"}}' >"$h/.claude/settings.json"
  export HOME=$h FAKE_LOG=$work/$1.calls; : >"$FAKE_LOG"
}
snapshot() { (cd "$1" && find . -type f -not -path './.local/*' -not -name '*.bak.graphite-*' -not -name '*.after-graphite-*' | sort | xargs md5sum); }
# Safety: never run the scripts unless HOME is inside the temp folder.
guard() { case $HOME in "$work"/*) ;; *) echo "test-install: HOME is not a temp folder ($HOME); stopping" >&2; exit 2 ;; esac; }
scripts=${SCRIPTS_DIR:-$root/scripts} # SCRIPTS_DIR=folder tests another copy of install.sh and uninstall.sh
inst()   { guard; PATH=$fakebin:$PATH "$scripts/install.sh" "$@"; }
uninst() { guard; PATH=$fakebin:$PATH "$scripts/uninstall.sh" "$@"; }

echo "== A: dry-run, install, repeat, uninstall"
new_home a; snapshot "$h" >"$work/a.before"
inst --dry-run >/dev/null; check "dry-run changes nothing" '[ "$(snapshot "$h")" = "$(cat $work/a.before)" ] && [ ! -d "$h/.local" ] && ! ls "$h"/.config/*/*.bak.* >/dev/null 2>&1'
inst >/dev/null; check "install writes the theme, status line and settings" '[ -f "$h/.claude/themes/graphite.json" ] && [ -x "$h/.claude/graphite-statusline.sh" ] && [ "$(jq -r .theme "$h/.claude/settings.json")" = custom:graphite ] && [ "$(jq -r .env.A "$h/.claude/settings.json")" = 1 ]'
out=$(inst); check "second install changes nothing and writes no manifest" 'echo "$out" | grep -q "nothing changed" && [ "$(ls "$h"/.local/state/herdr-graphite/ | wc -l)" = 1 ]'
uninst >/dev/null; check "uninstall restores every file" '[ "$(snapshot "$h")" = "$(cat $work/a.before)" ]'
check "item 5: no .after-graphite copy when no file changed" '! ls "$h"/.config/*/*.after-graphite-* "$h"/.claude/*.after-graphite-* >/dev/null 2>&1'
check "manifest is marked .undone" 'ls "$h"/.local/state/herdr-graphite/ | grep -q "undone$"'

echo "== B: a file changed after the install keeps its copy"
new_home b; inst >/dev/null
echo 'my later edit' >>"$h/.config/ghostty/config"
uninst >/dev/null
check "changed file is restored from the backup" '[ "$(cat "$h/.config/ghostty/config")" = "seed ghostty config" ]'
check "changed file leaves one .after-graphite copy with the edit" '[ "$(ls "$h"/.config/ghostty/config.after-graphite-* | wc -l)" = 1 ] && grep -q "my later edit" "$h"/.config/ghostty/config.after-graphite-*'
check "unchanged files leave no copy" '! ls "$h"/.config/herdr/*.after-graphite-* >/dev/null 2>&1'

echo "== B2: settings.json changed after the install"
new_home g; inst >/dev/null
jq '.later = 1' "$h/.claude/settings.json" >"$h/s.tmp" && mv "$h/s.tmp" "$h/.claude/settings.json"
uninst >/dev/null
check "later key stays, theme is back to the old value, statusLine is gone" '[ "$(jq -r .later "$h/.claude/settings.json")" = 1 ] && [ "$(jq -r .theme "$h/.claude/settings.json")" = dark ] && [ "$(jq -r .statusLine "$h/.claude/settings.json")" = null ]'

echo "== C: item 3: --set-default-terminal without Ghostty"
new_home c; snapshot "$h" >"$work/c.before"
# Hide the fake ghostty: a PATH with only the fake omarchy-default-terminal and the system tools.
mkdir -p "$work/bin-noghostty"; cp "$fakebin/omarchy-default-terminal" "$work/bin-noghostty/"
guard
if PATH=$work/bin-noghostty:$(echo "$PATH" | tr ':' '\n' | grep -v '^$' | while read -r d; do [ -x "$d/ghostty" ] || printf '%s:' "$d"; done) "$scripts/install.sh" --set-default-terminal >"$work/c.out" 2>&1; then bad "refuses without Ghostty"; else ok "refuses without Ghostty (exit 1)"; fi
check "it says why" 'grep -q "needs Ghostty" "$work/c.out"'
check "nothing changed, no terminal call" '[ "$(snapshot "$h")" = "$(cat $work/c.before)" ] && [ ! -d "$h/.local" ] && [ ! -s "$FAKE_LOG" ]'
inst --set-default-terminal --dry-run >/dev/null 2>&1; check "dry-run with --with-ghostty and --set-default-terminal plans, changes nothing" '[ "$(snapshot "$h")" = "$(cat $work/c.before)" ]'

echo "== D: item 4: unknown old default terminal"
new_home d; printf '# mine\nsome.unknown.desktop\n' >"$h/.config/xdg-terminals.list"; cp "$h/.config/xdg-terminals.list" "$work/d.list"
inst --set-default-terminal >/dev/null
check "terminals list now names Ghostty" 'grep -q ghostty "$h/.config/xdg-terminals.list"'
uninst >"$work/d.out" 2>&1; st=$?
check "uninstall exits 0" '[ $st = 0 ]'
check "terminals list is back byte for byte" 'cmp -s "$h/.config/xdg-terminals.list" "$work/d.list"'
check "uninstall never calls omarchy-default-terminal (only the install did, once)" '[ "$(wc -l <"$FAKE_LOG")" = 1 ]'
check "manifest is marked .undone" 'ls "$h"/.local/state/herdr-graphite/ | grep -q "undone$"'
uninst >"$work/d2.out" 2>&1; check "a second uninstall reports no manifest, with no warning about backups" 'grep -q "no manifest" "$work/d2.out" && ! grep -q "backup .* missing" "$work/d2.out"'

echo "== E: no terminals list before"
new_home e; inst --set-default-terminal >/dev/null
check "list created" '[ -f "$h/.config/xdg-terminals.list" ]'
uninst >/dev/null; check "list removed again" '[ ! -e "$h/.config/xdg-terminals.list" ]'

echo "== F: two installs need two uninstalls (newest first)"
new_home f; snapshot "$h" >"$work/f.before"
inst >/dev/null; inst --set-default-terminal >/dev/null
check "two manifests" '[ "$(ls "$h"/.local/state/herdr-graphite/install-*.json | wc -l)" = 2 ]'
uninst >/dev/null
check "first uninstall undoes only the newest (terminals list gone, configs still Graphite)" '[ ! -e "$h/.config/xdg-terminals.list" ] && grep -q Graphite "$h/.config/ghostty/config" || grep -q "herdr-graphite" "$h/.config/ghostty/config"'
uninst >/dev/null
check "second uninstall restores everything" '[ "$(snapshot "$h")" = "$(cat $work/f.before)" ]'

exit $fail
