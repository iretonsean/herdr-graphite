#!/usr/bin/env bash
# Renders docs/screenshots/H3a-sidebar.png: the Graphite app with demo data in a throwaway headless Weston.
# Nothing opens on your desktop and your herdr is not touched: a fake `herdr` prints app/demo/agents.json, and the
# feed files are copies of app/demo/feed-*.json with start times set relative to now.
# Usage: scripts/render-app-shots.sh
# Needs: weston (15), quickshell, jq, magick, weston-screenshooter.
set -euo pipefail
ulimit -c 0 # no core dumps, so no crash toast on your desktop
root=$(git rev-parse --show-toplevel)
work=$(mktemp -d "${TMPDIR:-/tmp}/herdr-graphite-app.XXXXXX")
sock=herdr-graphite-app-$$
wpid= qpid=
cleanup() {
  [ -n "$qpid" ] && kill "$qpid" 2>/dev/null || true
  [ -n "$wpid" ] && kill "$wpid" 2>/dev/null || true
  [ -n "${KEEP_WORK:-}" ] && echo "kept $work" || rm -rf "$work"
}
trap cleanup EXIT

# Demo data: the start time of each session is set to "N seconds ago".
mkdir -p "$work/feed" "$work/state"
declare -A ago=([w1_p1]=720 [w1_p2]=1860 [w1_p3]=3600 [w2_p2]=240)
for f in "$root"/app/demo/feed-*.json; do
  k=$(basename "$f" .json); k=${k#feed-}
  jq --argjson ago "${ago[$k]:-60}" '.started = ((now|floor) - $ago) | .updated = (now|floor)' "$f" >"$work/feed/$k.json"
done
cat >"$work/herdr" <<SH
#!/usr/bin/env bash
[ "\$1 \$2" = "agent list" ] && cat "$root/app/demo/agents.json"
SH
chmod +x "$work/herdr"

# Headless Weston has no seat, and Qt draws no frame without one. A synth-input module adds a keyboard and pointer.
synth=${SYNTH_SO:-}
[ -n "$synth" ] || { echo "set SYNTH_SO=/path/to/synth-input.so (a Weston module that adds a seat)" >&2; exit 1; }
export WESTON_SYNTH_SOCKET=$XDG_RUNTIME_DIR/$sock-synth
env -u WAYLAND_DISPLAY -u DISPLAY weston --modules="$synth" --backend=headless --renderer=gl --socket="$sock" --width=1100 --height=900 \
  --scale=2 --idle-time=0 --shell=kiosk --debug --log="$work/weston.log" >/dev/null 2>&1 &
wpid=$!
for _ in $(seq 100); do [ -S "$XDG_RUNTIME_DIR/$sock" ] && break; sleep 0.1; done
[ -S "$XDG_RUNTIME_DIR/$sock" ] || { echo "weston did not start: $work/weston.log" >&2; exit 1; }

env -u DISPLAY -u DBUS_SESSION_BUS_ADDRESS WAYLAND_DISPLAY="$sock" QT_QPA_PLATFORM=wayland QT_QUICK_BACKEND=${QT_QUICK_BACKEND:-software} HG_WIDTH=1100 HG_HEIGHT=900 \
  HERDR_BIN="$work/herdr" HERDR_FEED_DIR="$work/feed" HERDR_GRAPHITE_HOST=workstation XDG_STATE_HOME="$work/state" NO_AT_BRIDGE=1 \
  quickshell -p "$root/app/shell.qml" >"$work/app.log" 2>&1 &
qpid=$!
sleep 7
# Move the pointer to the corner, so that no hover shows.
python3 -I -c 'import socket,sys; c=socket.socket(socket.AF_UNIX); c.connect(sys.argv[1]); c.send(b"move 1099 899\n"); c.recv(16)' "$WESTON_SYNTH_SOCKET" || true
sleep 1
(cd "$work" && WAYLAND_DISPLAY="$sock" weston-screenshooter >/dev/null 2>&1)
mkdir -p "$root/docs/screenshots"
full=$(ls "$work"/wayland-screenshot-*.png | head -1)
magick "$full" -resize 50% "$work/full.png"
magick "$work/full.png" -crop 336x900+0+0 +repage "$root/docs/screenshots/H3a-sidebar.png"
cp "$work/full.png" "${APP_FULL_SHOT:-$work/full.png}" 2>/dev/null || true
echo "wrote docs/screenshots/H3a-sidebar.png"
[ -z "${APP_FULL_SHOT:-}" ] || echo "full window: $APP_FULL_SHOT"
grep -i -E "error|warn" "$work/app.log" | grep -v -i -E "gtk|dbind|accessib" || true
