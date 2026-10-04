# tidy-harness

A small, well-engineered LLM harness core, built from evidence (real session logs) and from the mistakes of an earlier
suite of native Mac apps (`~/maccyapps`, see ARCHITECTURE.md §Lessons).

    ./check.sh                              # the one gate: build + unit tests + catalog-vs-probes + conformance on your real sessions
    .build/debug/harness lens               # what do agents actually do, from ~/.pi/agent/sessions
    .build/debug/harness lens DIR --json    # the machine-comparable summary
    .build/debug/harness rules              # the rule catalog: source text -> sensors (lens/probe/gate) -> gaps

Needs: Swift 6.1 (Command Line Tools is enough, no Xcode), `jq`, `bb` (babashka), and for the catalog check
`~/pi-harness/eval/probes.edn` (override with `PROBES_EDN`). The bb reference scorecard lives here: `reference/scorecard.bb`.

Status: slice 2. `HarnessCore` reads the pi session log and computes the deterministic lens; it agrees exactly with the
bb reference on every real session. The rule catalog ties doctrine text to its sensors and shows the gaps.
Gates, model/tool adapters and the macOS app do not exist yet — see NEEDS.md.
