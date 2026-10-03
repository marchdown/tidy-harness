# tidy-harness

A small, well-engineered LLM harness core, built from evidence (real session logs) and from the mistakes of an earlier
suite of native Mac apps (`~/maccyapps`, see ARCHITECTURE.md §Lessons).

    ./check.sh        # build + unit tests + conformance against the bb reference, on your real sessions. One command, one verdict.
    .build/debug/harness lens            # what do agents actually do, from ~/.pi/agent/sessions
    .build/debug/harness lens DIR --json # the machine-comparable summary

Needs: Swift 6.1 (Command Line Tools is enough, no Xcode), `jq`, `bb` (babashka), and the bb reference scorecard
at `~/pi-doctrine-prod/bin/scorecard.bb` (override with `SCORECARD_BB`).

Status: slice 1. `HarnessCore` reads the pi session log and computes the deterministic lens; it agrees exactly with the
bb reference on every real session. Gates, the model/tool adapters and the macOS app do not exist yet — see NEEDS.md.
