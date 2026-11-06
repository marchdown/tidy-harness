#!/usr/bin/env bash
# catalog-check.sh — the rule catalog and the controlled probes must describe the same world.
#   every probe in the probes file is claimed by exactly one catalog rule,
#   and every probe a rule claims exists. Nonzero exit on any mismatch.
# The probes file is a local input (it lives with the agent harness, not here). When it is
# absent the check is SKIPPED LOUDLY: it says so on stdout, writes a marker, and exits 0,
# so check.sh can report "green with skips" rather than lie or die.
set -euo pipefail
cd "$(dirname "$0")"
PROBES="${PROBES_EDN:-$HOME/pi-harness/eval/probes.edn}"
if [ ! -f "$PROBES" ]; then
  echo "SKIPPED catalog-vs-probes: no probes file at $PROBES (set PROBES_EDN to run it)"
  echo catalog >> "${CHECK_SKIPS:-/dev/null}"
  exit 0
fi
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
