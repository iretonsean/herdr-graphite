#!/usr/bin/env bash
# Renders each mockup to docs/screenshots/<file>.png with headless Chromium (nothing opens on the desktop).
# The mockups need the claude.ai Design canvas runtime. It is not in this repo: download it from your own
# canvas (artifact-type/dc-runtime.js) and pass its path.
# Usage: scripts/render-mockups.sh /path/to/dc-runtime.js
set -euo pipefail
runtime=${1:?usage: render-mockups.sh /path/to/dc-runtime.js}
root=$(git rev-parse --show-toplevel)
work=$(mktemp -d)
trap 'kill $server 2>/dev/null; rm -rf "$work"' EXIT
cp "$root"/mockups/*.dc.html "$work"/ && cp "$runtime" "$work"/support.js
python3 -I -m http.server 8765 --bind 127.0.0.1 --directory "$work" >/dev/null 2>&1 & server=$!
sleep 1
mkdir -p "$root/docs/screenshots"
for f in "$work"/*.dc.html; do
  name=$(basename "$f" .dc.html)
  chromium --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=2 \
    --window-size=1440,900 --virtual-time-budget=6000 \
    --screenshot="$root/docs/screenshots/$name.png" "http://127.0.0.1:8765/$name.dc.html" >/dev/null 2>&1
  echo "rendered $name"
done
echo "Check every image by hand before you commit it (see README, Privacy)."
