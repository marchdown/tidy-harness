#!/usr/bin/env bash
# check.sh — the ONE gate. Build, unit tests, catalog-vs-probes, then conformance of every implementation on real logs.
# Green here means green; there is no second script that disagrees. Nonzero exit on the first failure.
# Two checks need local inputs (a probes file, a directory of real session logs). Without them they
# skip loudly and the final line names what was skipped, so "green" never quietly means "half-run".
set -euo pipefail
cd "$(dirname "$0")"
export CHECK_SKIPS="$(mktemp -t check-skips)"
trap 'rm -f "$CHECK_SKIPS"' EXIT
echo "== build";       swift build 2>&1 | tail -1
echo "== unit tests";  swift test 2>&1 | grep -E "Test run with|✘" | tail -3
echo "== catalog";     ./catalog-check.sh
echo "== conformance"; ./conform.sh
rev="$(git rev-parse --short HEAD 2>/dev/null || echo 'uncommitted')"
if [ -s "$CHECK_SKIPS" ]; then
  echo "GREEN WITH SKIPS ($rev): skipped $(tr '\n' ' ' < "$CHECK_SKIPS")— supply the local inputs to run them"
else
  echo "ALL GREEN ($rev)"
fi
