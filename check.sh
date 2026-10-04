#!/usr/bin/env bash
# check.sh — the ONE gate. Build, unit tests, catalog-vs-probes, then conformance of every implementation on real logs.
# Green here means green; there is no second script that disagrees. Nonzero exit on the first failure.
set -euo pipefail
cd "$(dirname "$0")"
echo "== build";       swift build 2>&1 | tail -1
echo "== unit tests";  swift test 2>&1 | grep -E "Test run with|✘" | tail -3
echo "== catalog";     ./catalog-check.sh
echo "== conformance"; ./conform.sh
echo "ALL GREEN ($(git rev-parse --short HEAD 2>/dev/null || echo 'uncommitted'))"
