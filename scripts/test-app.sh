#!/usr/bin/env bash
# Tests the Graphite app's data layer with sample data. Nothing real is read: no herdr, no feed files of yours.
#   1. app/join.js (the join of `herdr agent list` and the feed files) in node
#   2. app/poll.sh with a fake herdr and a sample feed folder
# Usage: scripts/test-app.sh
set -u
root=$(git rev-parse --show-toplevel)
fail=0
node "$root/app/test-join.mjs" || fail=1

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
cat >"$work/herdr" <<SH
#!/usr/bin/env bash
[ "\$1 \$2" = "agent list" ] && cat "$root/app/demo/agents.json"
SH
chmod +x "$work/herdr"
mkdir "$work/feed"
for f in "$root"/app/demo/feed-*.json; do cp "$f" "$work/feed/$(basename "$f" .json | sed 's/^feed-//').json"; done
echo '{ not json' >"$work/feed/broken.json"
out=$(HERDR_BIN="$work/herdr" HERDR_FEED_DIR="$work/feed" bash "$root/app/poll.sh")
chk() { if jq -e "$1" <<<"$out" >/dev/null; then echo "ok   poll.sh: $2"; else echo "FAIL poll.sh: $2"; fail=1; fi; }
chk '(.agents|length)==5' 'five agents from herdr agent list'
chk '(.feed|length)==4' 'four feed files, the broken one skipped'
chk '.feed.w1_p1.title=="Fix Vercel POST hang"' 'feed keyed by the pane id with ":" as "_"'
chk '(.host|length)>0 and (.now|type)=="number"' 'host and time'
out=$(HERDR_BIN=/nonexistent HERDR_FEED_DIR="$work/none" bash "$root/app/poll.sh")
chk '(.agents|length)==0 and (.feed|length)==0' 'no herdr and no feed folder give empty lists, not an error'
[ $fail = 0 ] && echo "all app tests passed" || { echo "SOME APP TESTS FAILED"; exit 1; }
