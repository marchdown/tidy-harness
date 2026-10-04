#!/usr/bin/env bash
# conform.sh — do two independent implementations of the doctrine lens agree on the SAME logs?
#   reference: bb scorecard (Clojure)      candidate: swift HarnessCore (this repo)
# Both read spec/doctrine.json. The sessions are snapshotted first so a live, growing corpus cannot
# produce a false difference. Exit 0 = identical summaries; 1 = they disagree (diff shown); 2 = harness broke.
set -euo pipefail
cd "$(dirname "$0")"

SRC="${1:-$HOME/.pi/agent/sessions}"
REF="${SCORECARD_BB:-$PWD/reference/scorecard.bb}"
SNAP="$(mktemp -d -t conform)"
trap 'rm -rf "$SNAP"' EXIT

[ -d "$SRC" ] || { echo "no such sessions dir: $SRC" >&2; exit 2; }
[ -f "$REF" ] || { echo "no reference scorecard at $REF (set SCORECARD_BB)" >&2; exit 2; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 2; }

cp -R "$SRC" "$SNAP/sessions"
N=$(find "$SNAP/sessions" -name '*.jsonl' | wc -l | tr -d ' ')

swift build -q 2>&1 | grep -E "error" && { echo "swift build failed" >&2; exit 2; } || true
perl -e 'alarm 180; exec @ARGV' bb "$REF" "$SNAP/sessions" --spec spec/doctrine.json --summary "$SNAP/ref.json" >/dev/null
perl -e 'alarm 180; exec @ARGV' .build/debug/harness lens "$SNAP/sessions" --spec spec/doctrine.json --json > "$SNAP/cand.json"

jq -S . "$SNAP/ref.json"  > "$SNAP/ref.n.json"
jq -S . "$SNAP/cand.json" > "$SNAP/cand.n.json"

if diff -u "$SNAP/ref.n.json" "$SNAP/cand.n.json" > "$SNAP/diff.txt"; then
  echo "CONFORMS: bb reference and Swift core agree exactly on $N sessions ($(jq '.totals.turns' "$SNAP/ref.n.json") assistant turns, $(jq '.perModel|length' "$SNAP/ref.n.json") models)."
else
  echo "DISAGREE on $N sessions (reference vs candidate):"; head -60 "$SNAP/diff.txt"
  cp "$SNAP/diff.txt" /tmp/conform-diff.txt 2>/dev/null && echo "full diff: /tmp/conform-diff.txt"
  exit 1
fi
