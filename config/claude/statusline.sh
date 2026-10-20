#!/usr/bin/env bash
# Graphite status line for Claude Code: model, context bar, 5-hour session limit bar. No dollar costs.
# Claude Code sends one JSON object on stdin. Needs: bash, jq.
# Test:  scripts/test-statusline.sh
# Optional: GRAPHITE_STATUSLINE_NOW=<epoch seconds> fixes the clock (for tests).
set -u
input=$(cat)

# One jq call: model, context percent, session-limit percent, seconds until the session limit resets.
# Each field is checked alone: a wrong type hides only that field. The separator is the control character 0x1f,
# not a tab, because read joins empty fields that are split by white space (tab).
now=${GRAPHITE_STATUSLINE_NOW:-$(date +%s)}
IFS=$'\x1f' read -r model ctx lim reset < <(
  printf '%s' "$input" | jq -r --argjson now "$now" '
    def pct: if type == "number" then floor else "" end;
    [ (try .model.display_name catch null | if type == "string" and . != "" then . else "Claude" end),
      (try .context_window.used_percentage catch null | pct | if . == "" then 0 else . end),
      (try .rate_limits.five_hour.used_percentage catch null | pct),
      (try .rate_limits.five_hour.resets_at catch null | if type == "number" then ([. - $now, 0] | max | floor) else "" end)
    ] | map(tostring) | join("\u001f")' 2>/dev/null
) || true
[ -n "${model:-}" ] || { printf 'Claude'; exit 0; }

# Graphite colours (true colour). Bars are neutral; only warn and error use colour.
dim=$'\e[38;2;99;99;102m'      # text_4
label=$'\e[38;2;152;152;157m'  # text_3
text=$'\e[38;2;229;229;231m'   # text_2
track=$'\e[38;2;58;58;60m'     # empty part of a bar
ok=$'\e[38;2;152;152;157m'
warn=$'\e[38;2;255;204;102m'
err=$'\e[38;2;255;128;120m'
off=$'\e[0m'

bar() { # bar PERCENT -> 10-cell bar
  local p=$1 filled i c out=""
  [ "$p" -gt 100 ] && p=100
  filled=$(( (p * 10 + 50) / 100 ))
  if   [ "$p" -ge 90 ]; then c=$err
  elif [ "$p" -ge 70 ]; then c=$warn
  else c=$ok; fi
  out+=$c
  for ((i = 0; i < filled; i++)); do out+="━"; done
  out+=$track
  for ((i = filled; i < 10; i++)); do out+="━"; done
  printf '%s%s' "$out" "$off"
}

left() { # left SECONDS -> "2h 10m" or "45m"
  local s=$1
  if [ "$s" -ge 3600 ]; then printf '%dh %02dm' $((s / 3600)) $((s % 3600 / 60))
  else printf '%dm' $(((s + 59) / 60)); fi
}

sep="${dim}  ·  ${off}"
out="${text}${model}${off}${sep}${label}context${off} $(bar "$ctx") ${text}${ctx}%${off}"
if [ -n "${lim:-}" ]; then
  out+="${sep}${label}session limit${off} $(bar "$lim") ${text}${lim}%${off}"
  [ -n "${reset:-}" ] && out+=" ${dim}resets in $(left "$reset")${off}"
fi
printf '%s' "$out"
