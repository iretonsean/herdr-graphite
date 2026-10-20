#!/usr/bin/env bash
# Runs config/claude/statusline.sh with sample JSON input and checks the text it prints.
# Usage: scripts/test-statusline.sh
set -u
root=$(git rev-parse --show-toplevel)
sl=${STATUSLINE:-$root/config/claude/statusline.sh} # STATUSLINE=path tests another copy
export GRAPHITE_STATUSLINE_NOW=1000000
fail=0

strip() { sed -E 's/\x1b\[[0-9;]*m//g'; }
check() { # check NAME JSON EXPECTED-REGEX
  local out
  out=$(printf '%s' "$2" | "$sl" | strip)
  if printf '%s' "$out" | grep -qE -- "$3"; then echo "ok   $1: $out"
  else echo "FAIL $1: got [$out], want /$3/"; fail=1; fi
}
absent() { # absent NAME JSON REGEX-THAT-MUST-NOT-MATCH
  local out
  out=$(printf '%s' "$2" | "$sl" | strip)
  if printf '%s' "$out" | grep -qE -- "$3"; then echo "FAIL $1: got [$out], must not match /$3/"; fail=1
  else echo "ok   $1: $out"; fi
}

check "full input" '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":8.4},"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1007800}}}' \
  '^Opus  ·  context ━{10} 8%  ·  session limit ━{10} 23% resets in 2h 10m$'
check "high usage" '{"model":{"display_name":"Sonnet"},"context_window":{"used_percentage":91},"rate_limits":{"five_hour":{"used_percentage":96.9,"resets_at":1000600}}}' \
  'context ━{10} 91%.*session limit ━{10} 96% resets in 10m'
check "no limits (API user)" '{"model":{"display_name":"Haiku"},"context_window":{"used_percentage":40}}' \
  '^Haiku  ·  context ━{10} 40%$'
absent "no limits shows no session bar" '{"model":{"display_name":"Haiku"},"context_window":{"used_percentage":40}}' 'session'
check "context null early in a session" '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":null}}' \
  'context ━{10} 0%'
check "expired window" '{"model":{"display_name":"Opus"},"rate_limits":{"five_hour":{"used_percentage":50,"resets_at":999000}}}' \
  'session limit ━{10} 50% resets in 0m'
absent "no dollar costs" '{"model":{"display_name":"Opus"},"cost":{"total_cost_usd":12.5},"rate_limits":{"spend_limit":{"used_usd":3,"limit_usd":10,"used_percentage":30}}}' '\$|USD|[0-9]+\.[0-9]{2}'
check "empty input" '' '^Claude$'
check "invalid JSON" 'not json' '^Claude$'

# Review fixes: an empty field must stay in its own place, and a wrong type hides only that field.
absent "resets_at without used_percentage: no session bar, no 7800%" '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":10},"rate_limits":{"five_hour":{"resets_at":1007800}}}' 'session|7800'
check "resets_at without used_percentage: context stays" '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":10},"rate_limits":{"five_hour":{"resets_at":1007800}}}' \
  '^Opus  ·  context ━{10} 10%$'
check "ISO string in resets_at: bars stay, no time" '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":10},"rate_limits":{"five_hour":{"used_percentage":40,"resets_at":"2026-10-19T20:00:00Z"}}}' \
  '^Opus  ·  context ━{10} 10%  ·  session limit ━{10} 40%$'
check "string in used_percentage: that bar is hidden, the rest stays" '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":"lots"},"rate_limits":{"five_hour":{"used_percentage":40,"resets_at":1007800}}}' \
  '^Opus  ·  context ━{10} 0%  ·  session limit ━{10} 40% resets in 2h 10m$'
check "rate_limits is a string: model and context stay" '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":10},"rate_limits":"none"}' \
  '^Opus  ·  context ━{10} 10%$'
check "model is a number: name falls back to Claude" '{"model":{"display_name":5},"context_window":{"used_percentage":10}}' \
  '^Claude  ·  context ━{10} 10%$'
check "top-level array: Claude only or a safe line" '[]' '^Claude'

# Colour check: 70 % and 90 % change the bar colour.
c70=$(printf '%s' '{"model":{"display_name":"X"},"context_window":{"used_percentage":70}}' | "$sl" | grep -c $'38;2;255;204;102m')
c90=$(printf '%s' '{"model":{"display_name":"X"},"context_window":{"used_percentage":90}}' | "$sl" | grep -c $'38;2;255;128;120m')
c10=$(printf '%s' '{"model":{"display_name":"X"},"context_window":{"used_percentage":10}}' | "$sl" | grep -c $'38;2;255;204;102m')
if [ "$c70" = 1 ] && [ "$c90" = 1 ] && [ "$c10" = 0 ]; then echo "ok   colours: warn at 70, error at 90, neutral below"
else echo "FAIL colours: c70=$c70 c90=$c90 c10=$c10"; fail=1; fi

# Fill check: 40 % fills 4 of 10 cells (the part before the dark track colour).
filled=$(printf '%s' '{"model":{"display_name":"X"},"context_window":{"used_percentage":40}}' | "$sl" | sed -E 's/.*38;2;152;152;157m(━*)\x1b\[38;2;58;58;60m.*/\1/' | tr -d '\n' | wc -m)
if [ "$filled" = 4 ]; then echo "ok   fill: 40% fills 4 cells"; else echo "FAIL fill: 40% filled $filled cells"; fail=1; fi

exit $fail
