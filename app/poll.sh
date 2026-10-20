#!/usr/bin/env bash
# One read of everything the app shows, as one JSON line: {host, now, agents, feed}. It only reads:
# `herdr agent list` and the feed files. HERDR_BIN, HERDR_FEED_DIR and HERDR_GRAPHITE_HOST replace the defaults (tests and screenshots).
set -u
dir=${HERDR_FEED_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/herdr-graphite/feed}
host=${HERDR_GRAPHITE_HOST:-$(hostname 2>/dev/null || echo localhost)}
agents=$(timeout 5 "${HERDR_BIN:-herdr}" agent list 2>/dev/null </dev/null | jq -c '.result.agents // []' 2>/dev/null)
[ -n "$agents" ] || agents='[]'
feed='{}'
if [ -d "$dir" ]; then
  # Skip a file that is not valid JSON; keep the name without ".json" as the key.
  feed=$(for f in "$dir"/*.json; do [ -e "$f" ] || continue
    jq -c --arg k "$(basename "$f" .json)" '{($k): .}' "$f" 2>/dev/null
  done | jq -sc 'add // {}')
fi
jq -nc --arg host "$host" --argjson now "$(date +%s)" --argjson agents "$agents" --argjson feed "$feed" \
  '{host: $host, now: $now, agents: $agents, feed: $feed}'
