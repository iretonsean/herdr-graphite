#!/usr/bin/env bash
# Tests scripts/install-app.sh in a temporary data folder. Your real files are not touched.
set -u
root=$(git rev-parse --show-toplevel)
fail=0
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
ok() { echo "ok   $1"; }; bad() { echo "FAIL $1"; fail=1; }
run() { env HOME="$t/user" XDG_DATA_HOME="$t/data" "$root/scripts/install-app.sh" "$@"; }
f=$t/data/applications/herdr-graphite.desktop
mkdir -p "$t/user"

run --dry-run >/dev/null; [ ! -e "$f" ] && ok "--dry-run writes nothing" || bad "--dry-run writes nothing"
run >/dev/null; [ -f "$f" ] && ok "install writes the desktop entry" || bad "install writes the desktop entry"
grep -q '^Name=Herdr Graphite$' "$f" && ok "name is Herdr Graphite" || bad "name"
grep -q "^Exec=setsid uwsm-app -- quickshell -p \"$root/app/shell.qml\"\$" "$f" && ok "Exec runs quickshell through setsid uwsm-app" || bad "Exec line"
[ -f "$root/app/shell.qml" ] && ok "the QML file in Exec exists" || bad "the QML file in Exec exists"
if command -v desktop-file-validate >/dev/null; then
  desktop-file-validate "$f" && ok "desktop-file-validate passes" || bad "desktop-file-validate passes"
else echo "skip desktop-file-validate (not installed)"; fi
run >/dev/null; [ "$(ls "$t/data/applications" | wc -l)" = 1 ] && ok "a second install changes nothing else" || bad "a second install"
[ ! -e "$t/user/.local" ] && ok "nothing written under HOME" || bad "nothing written under HOME"
run --uninstall >/dev/null; [ ! -e "$f" ] && ok "--uninstall removes the entry" || bad "--uninstall removes the entry"
run --uninstall >/dev/null && ok "--uninstall twice is fine" || bad "--uninstall twice"
mkdir -p "$t/data/applications"; echo "[Desktop Entry]" >"$f"
run --uninstall >/dev/null 2>&1 && bad "a foreign file is kept" || { [ -f "$f" ] && ok "a file not made by the script is kept" || bad "a foreign file is kept"; }
# A path with a space and a quote.
rm -f "$f"; mkdir -p "$t/my repo/app" "$t/my repo/scripts"; cp "$root/scripts/install-app.sh" "$t/my repo/scripts/"; touch "$t/my repo/app/shell.qml"
git -C "$t/my repo" init -q
env HOME="$t/user" XDG_DATA_HOME="$t/data" "$t/my repo/scripts/install-app.sh" >/dev/null
grep -q "quickshell -p \"$t/my repo/app/shell.qml\"\$" "$f" && ok "a path with a space is quoted" || bad "a path with a space is quoted"
[ $fail = 0 ] && echo "all install tests passed" || { echo "SOME INSTALL TESTS FAILED"; exit 1; }
