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
out=$(HERDR_BIN="$work/herdr" HERDR_FEED_DIR="$work/feed" bash "$root/app/poll.sh")
chk() { if jq -e "$1" <<<"$out" >/dev/null; then echo "ok   poll.sh: $2"; else echo "FAIL poll.sh: $2"; fail=1; fi; }
chk '(.agents|length)==5' 'five agents from herdr agent list'
chk '(.feed|length)==4' 'four feed files'
chk '.feed.w1_p1.title=="Fix Vercel POST hang"' 'feed keyed by the pane id with ":" as "_"'
chk '(.host|length)>0 and (.now|type)=="number"' 'host and time'
out=$(HERDR_BIN=/nonexistent HERDR_FEED_DIR="$work/none" bash "$root/app/poll.sh")
chk '(.agents|length)==0 and (.feed|length)==0' 'no herdr and no feed folder give empty lists, not an error'
echo '{ not json' >"$work/feed/w2_p2.json"
out=$(HERDR_BIN="$work/herdr" HERDR_FEED_DIR="$work/feed" bash "$root/app/poll.sh")
chk '(.feed|length)==3 and (.agents|length)==5' 'a feed file that is not valid JSON is skipped'
out=$(HERDR_BIN=/nonexistent HERDR_FEED_DIR="$work/none" bash "$root/app/poll.sh")
chk '.herdrUp==false' 'herdrUp is false when herdr does not answer'
out=$(HERDR_BIN="$work/herdr" HERDR_FEED_DIR="$work/feed" bash "$root/app/poll.sh")
chk '.herdrUp==true' 'herdrUp is true when herdr answers'
# A feed folder of 400 files of 1 KB: only the files of listed panes are read, and nothing hits the argument limit.
for i in $(seq 400); do jq -nc --arg i "$i" '{title:("old"+$i),pad:("x"*1000)}' >"$work/feed/w9_p$i.json"; done
out=$(HERDR_BIN="$work/herdr" HERDR_FEED_DIR="$work/feed" bash "$root/app/poll.sh")
chk '(.feed|length)==3 and (.agents|length)==5' 'a big feed folder still works; files of panes that are gone are ignored'
# Many agents with big feed files: the whole JSON is far above 128 KiB.
big=$(jq -nc '{result:{agents:[range(300)|{agent:"claude",agent_status:"idle",cwd:"/w",pane_id:("b"+(.|tostring)+":p1")}]}}')
printf '#!/usr/bin/env bash\n[ "$1 $2" = "agent list" ] && printf %%s %q\n' "$big" >"$work/herdr-big"; chmod +x "$work/herdr-big"
mkdir "$work/feed2"; for i in $(seq 0 299); do jq -nc '{title:"t",pad:("x"*1000)}' >"$work/feed2/b${i}_p1.json"; done
out=$(HERDR_BIN="$work/herdr-big" HERDR_FEED_DIR="$work/feed2" bash "$root/app/poll.sh")
chk '(.agents|length)==300 and (.feed|length)==300' '300 agents with 300 KB of feed files (above the argument limit)'
[ $fail = 0 ] && echo "all app tests passed" || { echo "SOME APP TESTS FAILED"; exit 1; }
