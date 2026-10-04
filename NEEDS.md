# NEEDS — tidy-harness
## Goals
- A tidy LLM harness core: pure, evidence-built, doctrine-aware; UI-agnostic. Native macOS app = fork of Tzav (terminal + guard + ledger) over this core.
## Done (verified 2026-10-04)
- HarnessCore lens + `harness lens`; 15 unit tests; conformance exact vs bb on 72 real sessions; negative controls: conform fails on a broken reference, purity lint fails on `import AppKit`.
## Next (in order)
1. Gates as pure functions over (state, proposed action) -> Allow|Amend|Hold|Deny: done-when two-phase (pi A/B proved reject-and-retry fails, tool-lock works), network-timeout *Amend*, edit-needs-read *Hold*, approval-seam classes.
2. Counterfactual replay: run every real session through the gates, count would-be interventions (evidence for which gates earn their cost).
3. Model router policy from per-model failure stats (gemma-4-31b-it:free 52/52 error stops; qwen3.8 26%).
4. Adapters (model client, tool runner with default timeouts) behind effect interpreters.
5. macOS app: fork Tzav (VTCore/ScreenCore/KeyCore pure; PTY/Renderer impure), guard sheet + Ledger over HarnessCore. Build stamp in every binary.
## Needs from the user
- Name/home for the repo (working name tidy-harness at ~/tidy-harness) and a private remote (none exists yet).
- Whether the app forks KELIM's chassis (Atelier/Kelim.swift) or only the terminal cores.
_updated: 2026-10-04 · session: ~/.claude/projects/-Users-uprootiny-subdomrails/fe40f5a3-bf37-42dd-b606-f6988eb9931b_

## Integration pass (2026-10-04)
- Spec gained `rules` catalog (13 rules, each with source + sensors); refused at load if unsourced, unmeasured, duplicate, or naming an unknown lens. 21 tests.
- `harness rules` prints the matrix + gaps. catalog-check.sh: catalog == probes.edn (11 probes) — fails on an unknown probe (negative control done).
- Reference scorecard moved INTO this repo (reference/scorecard.bb); conform.sh no longer depends on another repo's branch; pi-doctrine-prod/bin/scorecard.bb is a forwarding wrapper (identical summary hash verified; fails loud with exit 2 if moved).
- OPEN: doc-anchor check for rule sources; lens predicates for the 7 probe-only rules (no-python-node, no-homebrew, keys-are-intentional, snapshot-before-destroy, no-heredoc-over-ssh, read-narrowly, fail-loud); first real gates.
