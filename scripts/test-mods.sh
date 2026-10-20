#!/usr/bin/env bash
# Runs all tests of the graphite plugin (H2): validate, unit tests with sample JSON, and the end-to-end feed test.
# Nothing of yours changes: the end-to-end test uses a throwaway herdr, a temporary Claude Code config and a fake API.
# Usage: scripts/test-mods.sh [--no-e2e]
set -u
root=$(git rev-parse --show-toplevel)
fail=0
echo "== claude plugin validate"; claude plugin validate "$root/mods/graphite" || fail=1
echo "== claude plugin validate (marketplace)"; claude plugin validate "$root" || fail=1
echo "== claude plugin test"; claude plugin test "$root/mods/graphite" || fail=1
if [ "${1:-}" != --no-e2e ]; then echo "== end-to-end feed test"; "$root/scripts/test-feed.sh" || fail=1; fi
[ $fail = 0 ] && echo "all mod tests passed" || echo "SOME MOD TESTS FAILED"
exit $fail
