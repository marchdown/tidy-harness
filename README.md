# tidy-harness

A small LLM harness core, built from evidence. The core is a pure function over an agent's
session log: rules are data (`spec/doctrine.json`), the lens that applies them is deterministic,
and a second, independent implementation (a Babashka script) must agree with it exactly on real
logs before either is trusted. Unknown is a value: a rule that does not apply reports *n/a*, not
*pass*.

    ./check.sh                              # the one gate: build + unit tests + catalog-vs-probes + conformance
    .build/debug/harness lens               # what agents actually do, from ~/.pi/agent/sessions
    .build/debug/harness lens DIR --json    # the machine-comparable summary
    .build/debug/harness rules              # the rule catalog: source text -> sensors (lens/probe/gate) -> gaps

Needs Swift 6.0 or later (Command Line Tools is enough, no Xcode) and `jq`. Two checks also need
local inputs: the catalog check reads a probes file (`PROBES_EDN`, default
`~/pi-harness/eval/probes.edn`) and the conformance check reads a directory of pi session logs
plus `bb` (Babashka) for the reference. Without them `check.sh` skips those two **loudly** and ends
with `GREEN WITH SKIPS`, naming what it skipped. It never reports `ALL GREEN` for a half-run.

Status: slice 2. `HarnessCore` reads the pi session log (JSONL) and computes the deterministic
lens; the bb reference scorecard (`reference/scorecard.bb`) is the second implementation and
`conform.sh` diffs their summaries. The rule catalog ties doctrine text to its sensors and shows
the gaps. Gates, model and tool adapters, and the macOS app do not exist yet; see `NEEDS.md`.
The design lessons it is built against, each with a mechanical counter, are in `ARCHITECTURE.md`.

UI legibility (a design brief made checkable): `bb ui/legibility.bb page.html` checks WCAG
contrast of every text and graphic colour in both colour schemes (resolving `var()` aliases),
viewport, lang and title, smallest font against the HIG floor, focus ring, reduced motion, touch
targets, and non-keyboard click targets. Read-only; exit 1 on any FAIL. It cannot judge
"comprehensible at a glance": it prints that checklist for a human.

Why this shape: a harness is an *oracle* for an agent's behaviour, a part the rest of a system
asks and trusts within stated limits. The limits here are written down: which logs it accepts,
what each rule means, and that two implementations agree before a number is believed.

License: MIT (see `LICENSE`).
