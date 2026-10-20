#!/usr/bin/env bash
# One read of everything the app shows, as one JSON line: {host, now, herdrUp, agents, feed}. It only reads:
# `herdr agent list` and the feed files of the panes in that list (a file of a pane that is gone is ignored).
# herdrUp is false when `herdr agent list` fails (herdr is not running). The data goes to jq on stdin, never as an
# argument (Linux limits one argument to 128 KiB).
# HERDR_BIN, HERDR_FEED_DIR and HERDR_GRAPHITE_HOST replace the defaults (tests and screenshots).
set -u
dir=${HERDR_FEED_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/herdr-graphite/feed}
host=${HERDR_GRAPHITE_HOST:-$(hostname 2>/dev/null || echo localhost)}
up=true
raw=$(timeout 5 "${HERDR_BIN:-herdr}" agent list 2>/dev/null </dev/null) || up=false
agents=$(printf '%s' "$raw" | jq -c '.result.agents // []' 2>/dev/null) || up=false
[ -n "$agents" ] || { agents='[]'; up=false; }
feed='{}'
if [ -d "$dir" ]; then
  # The file name is the pane id with every character outside A-Za-z0-9._- turned into "_".
  feed=$(printf '%s' "$agents" | jq -r '.[].pane_id // empty' | while read -r pane; do
    key=$(printf %s "$pane" | tr -c 'A-Za-z0-9._-' _)
    [ -f "$dir/$key.json" ] && jq -c --arg k "$key" '{($k): .}' "$dir/$key.json" 2>/dev/null
  done | jq -sc 'add // {}')
  [ -n "$feed" ] || feed='{}'
fi
{ printf '%s\n' "$agents"; printf '%s\n' "$feed"; } |
  jq -sc --arg host "$host" --argjson now "$(date +%s)" --argjson up "$up" \
    '{host: $host, now: $now, herdrUp: $up, agents: .[0], feed: .[1]}'
