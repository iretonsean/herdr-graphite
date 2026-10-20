#!/usr/bin/env bash
# End-to-end test of the H2 data feed. It runs the real Claude Code with the graphite plugin inside a throwaway herdr
# and checks what herdr shows (`herdr pane get`, `herdr agent list`). Nothing of yours is used or changed:
#   - herdr: its own server, socket, HOME and config (not your running herdr)
#   - Claude Code: a temporary CLAUDE_CONFIG_DIR, the plugin loaded with --plugin-dir, a fake API on 127.0.0.1
#     (scripts/demo/fake-anthropic.py answers with a scripted turn; no account, no network, no model)
#   - the host name in the test is "workstation" (a private UTS namespace); the project is a made-up demo repo
# Usage: scripts/test-feed.sh [LOGFILE]     LOGFILE gets a copy of the output (paths under your home are shortened).
# Needs: herdr, claude, python3, jq, git, script, unshare. Takes about 40 seconds.
set -u
ulimit -c 0 # no core dumps, so no crash toast on your desktop
root=$(git rev-parse --show-toplevel)
logfile=${1:-}
for c in herdr claude python3 jq git script unshare; do command -v "$c" >/dev/null || { echo "test-feed: $c is required" >&2; exit 1; }; done

work=$(mktemp -d "${TMPDIR:-/tmp}/herdr-graphite-feed.XXXXXX")
rt=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/hgf.XXXXXX") # a short path for the herdr socket (sockets allow about 100 characters)
chmod 700 "$rt"
home=$work/home sock=$rt/h.sock proj=$work/projects/acme-site cfg=$work/claude-config
port=$((18000 + RANDOM % 2000))
claude_bin=$(readlink -f "$(command -v claude)") # the real binary: a version-manager shim would read the temporary HOME
key=sk-ant-fake-key-for-the-feed-test-0001 # privacy-scan: allow (a made-up key for the fake API)
fail=0
mkdir -p "$home/.config/herdr" "$proj" "$cfg"

h() { env -u HERDR_ENV -u HERDR_PANE_ID -u HERDR_BIN_PATH -u HERDR_WORKSPACE_ID -u HERDR_TAB_ID -u HERDR_SESSION \
  HOME="$home" HERDR_SOCKET_PATH="$sock" herdr "$@"; }
out() { # out TEXT : print, and copy to the log file (home paths shortened)
  printf '%s\n' "$1"
  [ -z "$logfile" ] || printf '%s\n' "$1" | sed "s|$HOME|~|g; s|$work|\$WORK|g; s|$rt|\$RT|g" >>"$logfile"
}
ok()  { out "ok   $1"; }
bad() { out "FAIL $1"; fail=1; }
tok() { h pane get "$pane" 2>/dev/null | jq -r --arg k "$1" '.result.pane.tokens[$k] // ""'; }
label() { h pane get "$pane" 2>/dev/null | jq -r --arg k "$1" '.result.pane.state_labels[$k] // ""'; }
title() { h pane get "$pane" 2>/dev/null | jq -r '.result.pane.title // ""'; }
wait_for() { # wait_for SECONDS COMMAND... : poll until the command succeeds
  local n=$(($1 * 5)); shift
  while [ $n -gt 0 ]; do "$@" && return 0; sleep 0.2; n=$((n - 1)); done
  return 1
}
tok_is() { [ "$(tok "$1")" = "$2" ]; }
tok_has() { case "$(tok "$1")" in *"$2"*) return 0 ;; *) return 1 ;; esac; }
screen_has() { h pane read "$pane" 2>/dev/null | grep -q "$1"; }
check() { # check NAME COMMAND... : the command is a test
  local name=$1; shift
  if "$@"; then ok "$name"; else bad "$name"; fi
}
snapshot() { # snapshot TITLE : write what herdr shows into the log
  out ""; out "--- $1: herdr pane get"
  out "$(h pane get "$pane" | jq '.result.pane | {title, state_labels, tokens}')"
}

cleanup() {
  h server stop >/dev/null 2>&1
  [ -f "$work/api.pid" ] && kill "$(cat "$work/api.pid")" 2>/dev/null
  sleep 0.5
  rm -rf "$rt" "$work"
}
trap cleanup EXIT

# --- the demo project (made-up name): a git repository with a branch ---
git -C "$proj" init -q -b main
git -C "$proj" -c user.name=demo -c user.email=demo.invalid commit -q --allow-empty -m init
git -C "$proj" checkout -q -b fix/post-hang

# --- the temporary Claude Code config: onboarding done, the project trusted, the fake key approved ---
jq -n --arg proj "$proj" --arg tail "${key: -20}" \
  '{hasCompletedOnboarding: true, theme: "dark", numStartups: 5, customApiKeyResponses: {approved: [$tail], rejected: []},
    projects: {($proj): {hasTrustDialogAccepted: true, allowedTools: []}}}' >"$cfg/.claude.json"

# --- the fake API ---
setsid python3 "$root/scripts/demo/fake-anthropic.py" "$port" "$work/api.log" tasks "$proj" >/dev/null 2>&1 &
echo $! >"$work/api.pid"

# --- the throwaway herdr, in a private UTS namespace so that the host name is "workstation" ---
echo 'onboarding = false' >"$home/.config/herdr/config.toml"
(
  cd "$work" || exit 1
  env -i PATH="$PATH" HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_STATE_HOME="$home/.local/state" XDG_DATA_HOME="$home/.local/share" \
    XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-$rt}" HERDR_SOCKET_PATH="$sock" HERDR_CONFIG_PATH="$home/.config/herdr/config.toml" \
    SHELL=/bin/bash TERM=xterm-256color \
    setsid script -qfc "stty rows 50 cols 150; unshare --user --map-root-user --uts sh -c 'hostname workstation; exec herdr'" /dev/null \
    >"$work/herdr-term.log" 2>&1 &
)
pane=
find_pane() { pane=$(h pane list 2>/dev/null | jq -r '.result.panes[0].pane_id // empty'); [ -n "$pane" ]; }
wait_for 20 find_pane || { echo "test-feed: the test herdr did not start" >&2; exit 1; }
sleep 1

out "H2 data feed, end-to-end test ($(date '+%Y-%m-%d %H:%M'))"
out "herdr $(h --version 2>/dev/null | head -1)   claude $("$claude_bin" --version 2>/dev/null | head -1)"
out "pane $pane in a throwaway herdr; Claude Code with the graphite plugin and a fake API"

# --- start Claude Code in the pane ---
h pane run "$pane" "clear; cd $proj && env CLAUDE_CONFIG_DIR=$cfg CLAUDE_CODE_ENABLE_TODO_TOOLS=1 ANTHROPIC_BASE_URL=http://127.0.0.1:$port ANTHROPIC_API_KEY=$key DISABLE_AUTOUPDATER=1 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 $claude_bin --model claude-opus-5-5 --permission-mode default --plugin-dir $root/mods/graphite --debug-file $work/claude-debug.log" >/dev/null
check "Claude Code starts and shows its prompt" wait_for 30 screen_has "Claude Code v"
wait_for 10 tok_is state ready
snapshot "after start"
check "start: state is ready"                    tok_is state ready
check "start: machine is the host name"          tok_is machine workstation
check "start: project is the repository folder"  tok_is project acme-site
check "start: branch"                            tok_is branch fix/post-hang
check "start: model"                             tok_is model "Opus 5.5"
check "start: reply style is brief"              tok_is mode brief
check "start: started time is set"               test -n "$(tok started)"
check "start: the idle label says Ready"         test "$(label idle)" = Ready

# --- a prompt: title, working, plan steps, then a permission question ---
h pane send-text "$pane" "Fix the Vercel POST hang" >/dev/null
h pane send-keys "$pane" enter >/dev/null
check "prompt: state is working"                 wait_for 10 tok_is state working
check "prompt: title is the first prompt"        test "$(title)" = "Fix the Vercel POST hang"
check "plan: first step runs (steps has n)"      wait_for 10 tok_has steps n
check "plan: step names what runs now"           wait_for 10 tok_is step "Reading the form code"
snapshot "working, step 1"
check "plan: step 1 done, step 2 runs"           wait_for 15 tok_is steps dn
check "needs you: state is needs"                wait_for 25 tok_is state needs
check "needs you: the ask says what waits"       tok_has ask permission
snapshot "needs you"
out ""; out "--- herdr agent list"; out "$(h agent list | jq -c '.result.agents')"

# --- approve the question: the turn ends ---
h pane send-keys "$pane" enter >/dev/null
check "done: state is done"                      wait_for 25 tok_is state done
check "done: all steps done"                     tok_is steps dd
check "done: last line is the result"            tok_is last "The form works again."
check "done: context percent is a number"        test -n "$(tok context)"
check "done: the ask is cleared"                 test -z "$(tok ask)"
check "done: since is not before started"        test "$(tok since)" -ge "$(tok started)"
snapshot "done"

# --- the feed file for the Graphite app ---
file=$home/.local/state/herdr-graphite/feed/$(printf %s "$pane" | tr -c 'A-Za-z0-9._-' _).json
check "feed file: valid JSON with the 2 plan items" test "$(jq '.plan.items | length' "$file" 2>/dev/null)" = 2
check "feed file: step names and times are kept"   test "$(jq -r '.plan.items[0].name' "$file" 2>/dev/null)" = "Read the form code"
check "feed file: herdr reported no error"         test ! -s "$file.err"

# --- /full: the next prompt announces the switch, and the feed shows the mode ---
h pane send-text "$pane" "/full" >/dev/null
h pane send-keys "$pane" enter >/dev/null
check "/full: Claude Code answers the command"   wait_for 10 screen_has "Reply style set to Full"
h pane send-text "$pane" "Explain it" >/dev/null
h pane send-keys "$pane" enter >/dev/null
check "/full: the feed shows mode full"          wait_for 15 tok_is mode full
check "/full: the turn ends"                     wait_for 15 tok_is state done
check "reply style: the system prompt had the Brief rule" grep -q "style=Brief" "$work/api.log"
check "reply style: the next prompt announced Full"       grep -q "style=.*Full" "$work/api.log"

# --- speed: the engine's own debug log times each hook of the plugin (next() included, which is only the engine's work) ---
slowest() { # the longest time in ms of a classic hook of the plugin
  grep -o 'graphite@inline classic\.[A-Za-z]* settled in [0-9.]*ms' "$work/claude-debug.log" | sed 's/.* in //; s/ms//' | sort -n | tail -1
}
out ""; out "--- hook times (ms): $(grep -o 'graphite@inline classic\.[A-Za-z]* settled in [0-9.]*ms' "$work/claude-debug.log" | sed 's/graphite@inline classic\.//; s/ settled in /=/' | tr '\n' ' ')"
check "speed: every hook returns in under 200 ms (slowest $(slowest) ms)" awk -v t="$(slowest)" 'BEGIN { exit !(t != "" && t < 200) }'

# --- exit: the feed clears what it set ---
h pane send-text "$pane" "/exit" >/dev/null
h pane send-keys "$pane" enter >/dev/null
check "exit: the state token is cleared"         wait_for 15 tok_is state ""
check "exit: the title is cleared"               test -z "$(title)"
check "exit: the feed file is removed"           test ! -e "$file"
snapshot "after exit"

out ""
if [ $fail = 0 ]; then out "all checks passed"; else out "SOME CHECKS FAILED"; fi
exit $fail
