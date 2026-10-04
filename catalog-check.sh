#!/usr/bin/env bash
# catalog-check.sh — the rule catalog and the controlled probes must describe the same world.
#   every probe in ~/pi-harness/eval/probes.edn is claimed by exactly one catalog rule,
#   and every probe a rule claims exists. Nonzero exit on any mismatch; never silently skipped.
set -euo pipefail
cd "$(dirname "$0")"
PROBES="${PROBES_EDN:-$HOME/pi-harness/eval/probes.edn}"
[ -f "$PROBES" ] || { echo "no probes file at $PROBES (set PROBES_EDN)" >&2; exit 2; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 2; }

have=$(grep -o -E ':id :[a-z0-9-]+' "$PROBES" | sed 's/^:id ://' | sort -u)
claimed=$(jq -r '.rules[].probes[]' spec/doctrine.json | sort)
bad=0
unclaimed=$(comm -23 <(echo "$have") <(echo "$claimed" | sort -u))
missing=$(comm -13 <(echo "$have") <(echo "$claimed" | sort -u))
dups=$(echo "$claimed" | uniq -d)
[ -z "$unclaimed" ] || { echo "probes with no catalog rule: $(echo $unclaimed)"; bad=1; }
[ -z "$missing" ]   || { echo "catalog names probes that do not exist: $(echo $missing)"; bad=1; }
[ -z "$dups" ]      || { echo "probes claimed by more than one rule: $(echo $dups)"; bad=1; }
[ $bad = 0 ] || exit 1
echo "catalog and probes agree: $(echo "$have" | wc -l | tr -d ' ') probes, $(jq '.rules|length' spec/doctrine.json) rules"
