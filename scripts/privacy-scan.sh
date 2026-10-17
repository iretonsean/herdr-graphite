#!/usr/bin/env bash
# Checks every tracked or staged file for private data before a push.
# Generic checks are here. Your own private words go in a file outside the repo:
#   ${XDG_CONFIG_HOME:-~/.config}/herdr-graphite/private-terms.txt   (one regex per line, # for comments)
# Exit 1 when something matches. Run: scripts/privacy-scan.sh
# Install as a pre-push hook: ln -s ../../scripts/privacy-scan.sh .git/hooks/pre-push
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 2

terms_file="${XDG_CONFIG_HOME:-$HOME/.config}/herdr-graphite/private-terms.txt"
patterns=(
  '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'   # email addresses
  '/home/[a-z_][a-z0-9_-]*'                            # home folders
  '/Users/[A-Za-z0-9_-]+'                              # macOS home folders
  '(^|[^0-9.])(10|192\.168|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]{1,3}\.[0-9]{1,3}' # private IP addresses
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'                 # private keys
  '(gh[pousr]_[A-Za-z0-9]{20,}|sk-ant-[A-Za-z0-9_-]{10,}|AKIA[0-9A-Z]{16})' # tokens
  '([0-9a-f]{2}:){5}[0-9a-f]{2}'                       # MAC addresses
)
# Lines with this marker are allowed (for example, this script's own patterns).
allow='privacy-scan: allow'

files=$(git ls-files --cached --others --exclude-standard)
[ -z "$files" ] && { echo "privacy-scan: no files"; exit 0; }

found=0
check() {
  local pat=$1 flags=$2
  # shellcheck disable=SC2086
  out=$(printf '%s\n' "$files" | xargs -d '\n' grep -n $flags -E -- "$pat" 2>/dev/null | grep -v "$allow" | grep -v '^scripts/privacy-scan.sh:')
  if [ -n "$out" ]; then
    echo "privacy-scan: pattern [$pat] matches:"
    printf '%s\n' "$out" | head -20
    found=1
  fi
}
for p in "${patterns[@]}"; do check "$p" ""; done
if [ -f "$terms_file" ]; then
  while IFS= read -r line; do
    case $line in ''|'#'*) continue ;; esac
    check "$line" "-i"
  done < "$terms_file"
else
  echo "privacy-scan: no private word list at $terms_file (only generic checks ran)"
fi

# Images cannot be read by grep: list them so a person checks each one.
imgs=$(printf '%s\n' "$files" | grep -iE '\.(png|jpe?g|gif|webp|mp4|webm)$')
[ -n "$imgs" ] && { echo "privacy-scan: check these images by hand:"; printf '  %s\n' $imgs; }

[ "$found" = 0 ] && echo "privacy-scan: clean"
exit $found
