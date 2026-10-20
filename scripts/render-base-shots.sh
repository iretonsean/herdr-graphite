#!/usr/bin/env bash
# Renders the H1 before/after screenshots in a throwaway headless Weston. Nothing opens on your desktop and
# nothing in your own config folders is read or changed: every run uses its own HOME and its own herdr server.
#   before: foot with the herdr look from before H1 (SF Mono, narrow padding, tab bar, dot indicators)
#   after:  Ghostty with config/ghostty and config/herdr, plus the Graphite status line
# The session is staged: workspaces, branches and agent states are made up (scripts/demo/claude is not Claude Code).
#
# Usage: scripts/render-base-shots.sh [--ghostty /path/to/ghostty] [--synth-so /path/to/synth-input.so] [--only before|after]
#   --ghostty   Ghostty binary. Default: ghostty from PATH. A package unpacked with bsdtar works (no install needed):
#               its share/ghostty and share/terminfo folders are found next to bin/.
#   --synth-so  A Weston module that adds a keyboard and pointer seat. foot (the "before" shot) needs a seat,
#               because headless Weston has none. Ghostty does not need one.
# Needs: weston (15), herdr, jq, git, magick, unshare. Output: docs/screenshots/H1-before.png and H1-after.png.
set -euo pipefail
ulimit -c 0 # no core dumps, so no crash toast on your desktop

root=$(git rev-parse --show-toplevel)
ghostty=ghostty synth_so= only=
while [ $# -gt 0 ]; do
  case $1 in
    --ghostty) ghostty=$2; shift 2 ;;
    --synth-so) synth_so=$2; shift 2 ;;
    --only) only=$2; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

work=$(mktemp -d "${TMPDIR:-/tmp}/herdr-graphite-shots.XXXXXX")
rt=$(mktemp -d "${XDG_RUNTIME_DIR:?}/hgs.XXXXXX") # a short path for the herdr socket (sockets allow about 100 characters)
sock=herdr-graphite-shots-$$
wpid= tpid=
cleanup() {
  [ -n "$tpid" ] && kill "$tpid" 2>/dev/null || true
  for p in $(pgrep -f "$work/" 2>/dev/null || true); do [ "$p" != "$$" ] && kill "$p" 2>/dev/null || true; done
  [ -n "$wpid" ] && kill "$wpid" 2>/dev/null || true
  rm -rf "$rt"
  [ -n "${KEEP_WORK:-}" ] && echo "kept $work" || rm -rf "$work"
}
trap cleanup EXIT

# --- Demo projects (made-up names), each a small git repo with a branch and one change. ---
mk_repo() { # mk_repo NAME BRANCH
  local d=$work/projects/$1
  mkdir -p "$d" && git -C "$d" init -q -b main && echo "# $1" >"$d/README.md"
  git -C "$d" add . && git -C "$d" -c user.name=demo -c user.email=demo commit -q -m init
  [ "$2" = main ] || git -C "$d" checkout -q -b "$2"
  echo "change" >>"$d/README.md"
}
mk_repo canvas-app feat/dark-mode
mk_repo acme-site fix/nightly-build
mk_repo dashboard chore/drop-billing-tables
mk_repo dotfiles main

# --- Configs for one variant: prints the env prefix to use. ---
setup_variant() { # setup_variant before|after
  local v=$1 h=$work/$v/user
  mkdir -p "$h/.config/herdr" "$h/.config/foot" "$h/.config/ghostty" "$h/.local/state" "$work/$v/run"
  chmod 700 "$work/$v/run"
  if [ "$v" = before ]; then
    # The herdr look from before H1: terminal colours, dark panel, accent blue, tab bar, dot indicators.
    cat >"$h/.config/herdr/config.toml" <<'TOML'
onboarding = false
[theme]
name = "terminal"
[theme.custom]
panel_bg = "black"
[ui]
accent = "blue"
pane_gaps = false
pane_outer_borders = false
pane_scrollbars = false
confirm_close = false
prompt_new_tab_name = false
tab_bar_right = [{ type = "zoom" }, { type = "hostname" }]
TOML
    cat >"$h/.config/foot/foot.ini" <<'INI'
[main]
term=xterm-256color
font=SFMono Nerd Font Mono:size=9
pad=14x14
[colors]
background=1a1a1c
foreground=e5e5e7
regular0=1a1a1c
regular1=ff453a
regular2=32d74b
regular3=ffd60a
regular4=0a84ff
regular5=bf5af2
regular6=64d2ff
regular7=e5e5e7
bright0=3a3a3c
bright1=ff6961
bright2=5de37a
bright3=ffe066
bright4=409cff
bright5=da8fff
bright6=8ee0ff
bright7=f5f5f7
[cursor]
style=block
blink=no
INI
  else
    cp "$root/config/herdr/config.toml" "$h/.config/herdr/config.toml"
    cp "$root/config/ghostty/config" "$h/.config/ghostty/config"
  fi
}

session_env() { # session_env VARIANT -> env assignments for every process of the demo session
  local v=$1 h=$work/$v/user
  echo "-u HERDR_ENV -u HERDR_PANE_ID -u HERDR_BIN_PATH -u HERDR_SESSION -u HERDR_WORKSPACE_ID -u HERDR_TAB_ID" # not nested in your own herdr
  echo "HOME=$h XDG_CONFIG_HOME=$h/.config XDG_STATE_HOME=$h/.local/state XDG_DATA_HOME=$h/.local/share"
  echo "HERDR_CONFIG_PATH=$h/.config/herdr/config.toml HERDR_SOCKET_PATH=$rt/$v.sock"
  echo "PATH=$root/scripts/demo:$PATH DEMO_LOOK=$v SHELL=/bin/bash NO_AT_BRIDGE=1 GTK_USE_PORTAL=0 GIO_USE_VFS=local"
}

start_weston() { # start_weston VARIANT
  local v=$1 args=(--backend=headless --renderer=gl --socket="$sock-$v" --width=1100 --height=620 --scale=2
    --idle-time=0 --shell=kiosk --debug --log="$work/$v/weston.log")
  if [ "$v" = before ]; then
    [ -n "$synth_so" ] || { echo "the 'before' shot needs --synth-so (foot needs a seat)" >&2; exit 1; }
    export WESTON_SYNTH_SOCKET=$XDG_RUNTIME_DIR/$sock-synth-$v
    args+=(--modules="$synth_so")
  fi
  env -u WAYLAND_DISPLAY -u DISPLAY weston "${args[@]}" >/dev/null 2>&1 &
  wpid=$!
  for _ in $(seq 100); do [ -S "$XDG_RUNTIME_DIR/$sock-$v" ] && break; sleep 0.1; done
  [ -S "$XDG_RUNTIME_DIR/$sock-$v" ] || { echo "weston did not start: $work/$v/weston.log" >&2; exit 1; }
}

h() { # h VARIANT herdr-args... : run the herdr CLI inside the demo session
  local v=$1; shift
  env $(session_env "$v") herdr "$@"
}

stage() { # stage VARIANT : create the demo workspaces and agent states through herdr's CLI
  local v=$1 n=0 ws name state msg branch pane
  # The first workspace comes from the running client. Wait for it, then add the others.
  for _ in $(seq 100); do h "$v" workspace list >/dev/null 2>&1 && break; sleep 0.2; done
  sleep 1
  local first; first=$(h "$v" workspace list | jq -r '.. | objects | select(has("workspace_id")) | .workspace_id' | head -1)
  for spec in "canvas-app|idle||1" "acme-site|working||2" "dashboard|blocked|Needs your decision|3" "dotfiles|idle||4"; do
    IFS='|' read -r name state msg scene <<<"$spec"
    n=$((n + 1))
    if [ "$n" = 1 ]; then ws=$first; h "$v" workspace rename "$ws" "$name" >/dev/null; h "$v" workspace focus "$ws" >/dev/null
    else ws=$(h "$v" workspace create --cwd "$work/projects/$name" --label "$name" --no-focus | jq -r '.. | objects | select(has("workspace_id")) | .workspace_id' | head -1); fi
    pane=$(h "$v" pane list | jq -r --arg w "$ws" '.. | objects | select(.workspace_id? == $w and has("pane_id")) | .pane_id' | head -1)
    h "$v" pane run "$pane" "cd $work/projects/$name && DEMO_SCENE=$scene exec claude" >/dev/null
    sleep 1
    h "$v" pane report-agent "$pane" --source demo --agent claude --state "$state" ${msg:+--message "$msg"} --seq "$n" >/dev/null
  done
  h "$v" workspace focus "$first" >/dev/null
}

shoot() { # shoot VARIANT : save the terminal window (it fills the 1100x620 point screen)
  local v=$1 out=$root/docs/screenshots/H1-$v.png
  (cd "$work/$v" && WAYLAND_DISPLAY="$sock-$v" weston-screenshooter >/dev/null 2>&1)
  cp "$work/$v"/wayland-screenshot-*.png "$out"
  echo "wrote $out"
}

run_variant() { # run_variant before|after
  local v=$1
  setup_variant "$v"
  start_weston "$v"
  local term
  if [ "$v" = before ]; then term=(foot --config="$work/$v/user/.config/foot/foot.ini" --app-id=shots)
  else
    local share; share=$(cd "$(dirname "$(command -v "$ghostty")")/.." && pwd)/share
    term=(env GHOSTTY_RESOURCES_DIR="$share/ghostty" TERMINFO="$share/terminfo" "$ghostty" --gtk-single-instance=false)
  fi
  # A private user + UTS namespace gives the session the host name "workstation": the real one never shows.
  env -u DBUS_SESSION_BUS_ADDRESS $(session_env "$v") WAYLAND_DISPLAY="$sock-$v" GDK_BACKEND=wayland \
    "${term[@]}" -e unshare --user --map-root-user --uts sh -c 'hostname workstation; exec herdr' \
    >"$work/$v/term.log" 2>&1 &
  tpid=$!
  stage "$v"
  sleep 3
  # Move the pointer to the corner so its arrow is not in the picture (foot shows it).
  [ "$v" = before ] && python3 -I -c 'import socket,sys; c=socket.socket(socket.AF_UNIX); c.connect(sys.argv[1]); c.send(b"move 1099 619\n"); c.recv(16)' "$WESTON_SYNTH_SOCKET"
  sleep 1
  shoot "$v"
  h "$v" server stop >/dev/null 2>&1 || true
  kill "$tpid" 2>/dev/null || true; tpid=
  kill "$wpid" 2>/dev/null || true; wpid=
  sleep 1
}

mkdir -p "$root/docs/screenshots"
[ -z "$only" ] || [ "$only" = before ] && run_variant before
[ -z "$only" ] || [ "$only" = after ] && run_variant after
echo "Check each image by hand before you commit it (see README, Privacy)."
