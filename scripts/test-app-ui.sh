#!/usr/bin/env bash
# UI test of the Graphite app against a THROWAWAY herdr, in a headless Weston. It checks:
#   - the cards come from `herdr agent list` and the feed files (read from the app's own state dump, HG_DUMP)
#   - a click selects a card; a double click focuses that pane in herdr
#   - the message box: Enter sends the text with `herdr agent prompt`; Shift+Enter makes a new line (no send)
#   - a draft stays with its session; a prompt goes to the selected session also after the list reorders
#   - the error path: a prompt to an agent that waits for a decision shows herdr's error in the app
#   - herdr stopped: the sidebar says so
#   - closing the window ends only the app; the throwaway herdr keeps running
# Nothing of yours is used: own herdr server and socket, own HOME, own feed folder, own Weston. Your herdr is not touched.
# Usage: scripts/test-app-ui.sh [SHOTS_DIR]     SHOTS_DIR gets a picture after each step (look at them by hand).
# Needs: weston (15) with a synth-input module (SYNTH_SO), quickshell, herdr, jq, git, script, unshare, python3, magick.
set -u
ulimit -c 0
root=$(git rev-parse --show-toplevel)
shots=${1:-}
fail=0
work=$(mktemp -d "${TMPDIR:-/tmp}/herdr-graphite-ui.XXXXXX")
rt=$(mktemp -d "${XDG_RUNTIME_DIR:?}/hgu.XXXXXX"); chmod 700 "$rt"
home=$work/home hsock=$rt/h.sock wsock=hgu-$$
synth=${SYNTH_SO:-}
[ -n "$synth" ] || { echo "set SYNTH_SO=/path/to/synth-input.so" >&2; exit 1; }
export WESTON_SYNTH_SOCKET=$rt/synth
wpid= qpid=
mkdir -p "$home/.config/herdr" "$home/.local/state" "$work/feed" "$work/proj/canvas-app" "$work/proj/acme-site"
[ -z "$shots" ] || mkdir -p "$shots"

h() { env -u HERDR_ENV -u HERDR_PANE_ID -u HERDR_BIN_PATH -u HERDR_WORKSPACE_ID -u HERDR_TAB_ID -u HERDR_SESSION \
  HOME="$home" HERDR_SOCKET_PATH="$hsock" herdr "$@"; }
cleanup() {
  [ -n "$qpid" ] && kill "$qpid" 2>/dev/null
  h server stop >/dev/null 2>&1
  [ -n "$wpid" ] && kill "$wpid" 2>/dev/null
  sleep 0.5; rm -rf "$rt" "$work"
}
trap cleanup EXIT
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
check() { local n=$1; shift; if "$@"; then ok "$n"; else bad "$n"; fi; }
wait_for() { local n=$(($1 * 5)); shift; while [ $n -gt 0 ]; do "$@" && return 0; sleep 0.2; n=$((n - 1)); done; return 1; }
synth_cmd() { python3 -I -c 'import socket,sys; c=socket.socket(socket.AF_UNIX); c.connect(sys.argv[1]); c.send((sys.argv[2]+"\n").encode()); c.recv(64)' "$WESTON_SYNTH_SOCKET" "$1"; sleep 0.15; }
click() { synth_cmd "move $1 $2"; synth_cmd "click $1 $2"; }
dclick() { synth_cmd "move $1 $2"; synth_cmd "click $1 $2"; sleep 0.08; synth_cmd "click $1 $2"; }
key() { synth_cmd "key $1"; }
# Letters and digits to evdev key codes (US layout).
type_text() { local c i; for ((i = 0; i < ${#1}; i++)); do c=${1:i:1}; key "$(python3 -c "
r=dict(zip('qwertyuiop',range(16,26)));r.update(zip('asdfghjkl',range(30,39)));r.update(zip('zxcvbnm',range(44,51)));r[' ']=57
print(r['$c'])")"; done; }
shoot() { # shoot NAME
  [ -z "$shots" ] && return 0
  (cd "$work" && rm -f wayland-screenshot-*.png && WAYLAND_DISPLAY="$wsock" weston-screenshooter >/dev/null 2>&1)
  magick "$work"/wayland-screenshot-*.png -resize 50% "$shots/$1.png" 2>/dev/null
}

# --- the throwaway herdr, with two stand-in agents (scripts/demo/claude is not Claude Code) ---
echo 'onboarding = false' >"$home/.config/herdr/config.toml"
(cd "$work" && env -i PATH="$PATH" HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_STATE_HOME="$home/.local/state" \
  XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" HERDR_SOCKET_PATH="$hsock" HERDR_CONFIG_PATH="$home/.config/herdr/config.toml" \
  SHELL=/bin/bash TERM=xterm-256color \
  setsid script -qfc "stty rows 40 cols 120; unshare --user --map-root-user --uts sh -c 'hostname workstation; exec herdr'" /dev/null \
  >"$work/herdr-term.log" 2>&1 &)
panes() { h pane list 2>/dev/null | jq -r '.result.panes[].pane_id'; }
have_pane() { [ -n "$(panes)" ]; }
wait_for 20 have_pane || { echo "test-app-ui: the test herdr did not start" >&2; exit 1; }
sleep 1
p1=$(panes | head -1)
ws2=$(h workspace create --cwd "$work/proj/acme-site" --label acme-site --no-focus | jq -r '.. | objects | select(has("workspace_id")) | .workspace_id' | head -1)
sleep 1
p2=$(h pane list | jq -r --arg w "$ws2" '.result.panes[] | select(.workspace_id==$w) | .pane_id' | head -1)
h pane run "$p1" "cd $work/proj/canvas-app && DEMO_SCENE=2 PATH=$root/scripts/demo:\$PATH exec claude" >/dev/null
h pane run "$p2" "cd $work/proj/acme-site && DEMO_SCENE=3 PATH=$root/scripts/demo:\$PATH exec claude" >/dev/null
sleep 1.5
h pane report-agent "$p1" --source demo --agent claude --state working --seq 1 >/dev/null
h pane report-agent "$p2" --source demo --agent claude --state idle --seq 2 >/dev/null
h agent rename "$p1" builder >/dev/null; h agent rename "$p2" tester >/dev/null
two_agents() { [ "$(h agent list | jq '.result.agents|length')" = 2 ]; }
wait_for 10 two_agents || bad "the test herdr lists two agents"

# --- feed files for the two panes (made-up data), named like the plugin names them ---
now=$(date +%s)
mkfeed() { # mkfeed PANE TITLE PROJECT STATE LAST
  jq -nc --arg pane "$1" --arg title "$2" --arg project "$3" --arg state "$4" --arg last "$5" --argjson now "$now" \
    '{version:1,pane:$pane,machine:"workstation",project:$project,branch:"feat/demo",model:"Opus 5.5",title:$title,state:$state,last:$last,
      started:($now-600),since:($now-60),plan:{done:1,total:2,items:[{name:"Step one",doing:"Doing step one",status:"done",seconds:30},{name:"Step two",doing:"Doing step two",status:"now",seconds:null}]},
      context:40,weekly:55,weekly_reset:($now+86400),updated:$now}' >"$work/feed/$(printf %s "$1" | tr -c 'A-Za-z0-9._-' _).json"
}
mkfeed "$p1" "Build the demo" canvas-app working "Working on it"
mkfeed "$p2" "Test the demo" acme-site ready "Idle"

# --- Weston with a seat, then the app (talking to the throwaway herdr only) ---
env -u WAYLAND_DISPLAY -u DISPLAY weston --modules="$synth" --backend=headless --renderer=gl --socket="$wsock" \
  --width=1100 --height=700 --scale=2 --idle-time=0 --shell=kiosk --debug --log="$work/weston.log" >/dev/null 2>&1 &
wpid=$!
for _ in $(seq 100); do [ -S "$XDG_RUNTIME_DIR/$wsock" ] && break; sleep 0.1; done
start_app() { # start_app DUMPFILE
  rm -f "$1"
  env -i PATH="$PATH" HOME="$home" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" XDG_STATE_HOME="$home/.local/state" \
    WAYLAND_DISPLAY="$wsock" QT_QPA_PLATFORM=wayland QT_QUICK_BACKEND=software NO_AT_BRIDGE=1 HG_WIDTH=1100 HG_HEIGHT=700 \
    HG_DUMP="$1" HERDR_SOCKET_PATH="$hsock" HERDR_FEED_DIR="$work/feed" HERDR_GRAPHITE_HOST=workstation \
    quickshell -p "$root/app/shell.qml" >"$work/app.log" 2>&1 &
  qpid=$!
}
dumpf=$work/dump.json
dump() { jq -r "$1" "$dumpf" 2>/dev/null; }
dump_is() { [ "$(dump "$1")" = "$2" ]; }          # dump_is JQ-EXPR VALUE
dump_has() { dump "$1" | grep -q "$2"; }          # dump_has JQ-EXPR TEXT
start_app "$dumpf"
wait_for 20 test -s "$dumpf"
sleep 2
shoot 1-start
kb=$(h agent list | jq -r '.result.agents[] | select(.name=="builder") | .pane_id')
kt=$(h agent list | jq -r '.result.agents[] | select(.name=="tester") | .pane_id')

read_has() { h agent read "${2:-builder}" 2>/dev/null | grep -q "$1"; }
read_lacks() { ! read_has "$@"; }
focused() { h agent list | jq -r '.result.agents[] | select(.focused) | .name'; }
check "the app shows both sessions as cards, with the feed titles" dump_is '[.rows[] | select(.kind=="session") | .title] | sort | join(",")' "Build the demo,Test the demo"
check "the app shows the states from herdr (working, ready)" dump_is '[.rows[] | select(.kind=="session") | .state] | sort | join(",")' "ready,working"
check "the app selects the first session by itself" dump_is '.selected' "s:$kb"

# Cards (logical points, window 1100x700 at the screen origin): the first card is near y=222, the second near y=333.
h agent focus tester >/dev/null
sleep 1
click 150 333            # second card (tester)
sleep 1; shoot 2-selected
check "a click selects the card in the app" wait_for 4 dump_is '.selected' "s:$kt"
check "a single click only selects: herdr focus stays on the other pane" test "$(focused)" = tester
dclick 150 222
check "double click focuses the pane in herdr" wait_for 5 test "$(focused)" = builder
check "double click selects the card too" dump_is '.selected' "s:$kb"

# --- the message box ---
click 700 650
type_text "hello"
key 28                    # Enter
check "Enter sends the text to the selected agent" wait_for 8 read_has hello
check "the app says Sent and clears the box" wait_for 4 dump_is '.status + "|" + .draft' "Sent|"
sleep 0.5; shoot 3-sent
type_text "xqz"
synth_cmd "keydown 42"; key 28; synth_cmd "keyup 42"      # Shift+Enter
type_text "wvk"
sleep 0.3; shoot 4-newline
check "Shift+Enter does not send" read_lacks xqz
check "Shift+Enter makes a new line in the box" dump_is '.draft' "$(printf 'xqz\nwvk')"
key 28
check "Enter then sends both lines" wait_for 8 read_has wvk

# --- a draft stays with its session ---
type_text "dr"
click 150 333; sleep 0.5                                  # select tester
check "the draft of the other session is not in the box" dump_is '.draft' ""
click 700 650; type_text "zz"
click 150 222; sleep 0.5                                  # back to builder
check "the first draft comes back with its session" dump_is '.draft' "dr"
synth_cmd "keydown 29"; key 30; synth_cmd "keyup 29"; key 14   # Ctrl+A, Backspace: empty the box
click 150 333; sleep 0.5
synth_cmd "keydown 29"; key 30; synth_cmd "keyup 29"; key 14
click 150 222; sleep 0.5

# --- the list reorders while a session is selected: the text still goes to that session ---
h pane report-agent "$p2" --source demo --agent claude --state blocked --message "Needs your decision" --seq 3 >/dev/null
check "the card that needs you moves to the top" wait_for 8 dump_is '[.rows[] | select(.kind=="session")][0].title' "Test the demo"
sleep 1
check "the selection stays on the same session after the reorder" dump_is '.selected' "s:$kb"
click 700 650; type_text "xqzafter"; key 28
check "after the reorder the text goes to the selected session" wait_for 8 read_has xqzafter
check "and not to the session that moved to the top" read_lacks xqzafter tester

# --- the error path: tester is blocked, so herdr refuses a prompt, and the app shows why ---
click 150 222; sleep 0.5                                  # tester is on top now
check "the tester card is selected" dump_is '.selected' "s:$kt"
click 700 650; type_text "nope"; key 28
check "the app shows herdr's error" wait_for 6 dump_has '.status' blocked
check "the error is marked as failed, and the text stays in the box" dump_is '(.failed|tostring) + "|" + .draft' "true|nope"
sleep 0.5; shoot 5-error
check "the refused text was not typed into the agent" read_lacks nope tester

# --- Ctrl+W closes the window: the app ends, herdr and its agents stay ---
synth_cmd "keydown 29"; key 17; synth_cmd "keyup 29"
app_gone() { ! kill -0 "$qpid" 2>/dev/null; }
check "closing the window ends the app" wait_for 6 app_gone
check "herdr and its two agents are still there" two_agents

# --- herdr stopped: the sidebar says so ---
start_app "$dumpf"
wait_for 20 test -s "$dumpf"
h server stop >/dev/null 2>&1
check "with herdr stopped, the app knows" wait_for 10 dump_is '.herdrUp' false
sleep 1; shoot 6-herdr-down
check "the sidebar then has only the machine row" dump_is '.rows | length' 1
[ $fail = 0 ] && echo "all UI checks passed" || { echo "SOME UI CHECKS FAILED"; exit 1; }
