# Architecture (the brief)

## The abstraction
A harness is a **pure function over an event log**. Everything else is an interpreter of that function's output.

    log (pi JSONL, canonical)  ──fold──►  Facts / Summary        (the lens: what the agent actually did)
    state, proposed action     ──rule──►  Allow | Amend | Hold | Deny   (a gate; planned)
    effects as DATA            ──interpreter──►  model call, tool run, ask-human, persist   (adapters; planned)

* **Rules are data** (`spec/doctrine.json`). No implementation hardcodes a marker, pattern or threshold. One rule, many
  interpreters: the same definition is *measured* by the lens and (planned) *enforced* by a gate.
* **The core is pure** (`Sources/HarnessCore`): Foundation only, no clock, no I/O, no randomness. `PurityTests` fails the
  build otherwise. Callers hand it bytes and a spec; it hands back values.
* **Conformance, not trust.** A second implementation (the bb scorecard) must produce a byte-identical summary from the same
  logs. `./conform.sh` snapshots the corpus so a growing log cannot cause false differences.
* **Unknown is a value.** A rule that did not apply is `nil`, never counted as a pass (`Summary` keeps `[passed, applicable]`).
  Log lines that are not records are counted and reported, never dropped.

## Boundaries
    spec/        language-neutral: doctrine.json (rules as data)
    HarnessCore  pure: Event(log parse) · Doctrine(spec) · Lens(fold) · Summary(contract)
    harness      CLI client (impure, thin)
    (planned)    HarnessKit adapters · Gates · macOS app (fork of Tzav's terminal + guard + ledger) · web page

## Lessons from ~/maccyapps (KELIM), each with its mechanical counter
| Failure observed (2026-10-04) | Mechanism here |
|---|---|
| `./test.sh` red: generated `KenGenerated.swift` emits `Chord(…control:, command:)`; `check.sh` (drift gate) is not run by `test.sh` | `check.sh` is the only gate and runs everything |
| One monolithic test binary: one compile error silences every test | SwiftPM test target per module; failures are per-test |
| Built `.app`s older than their sources (Tzav 09-08 vs src 09-09; Ohel 09-09 vs 09-13), no stamp | planned: embed git hash + hash of inputs in every binary; `check` compares |
| "Core is pure" is a convention | `PurityTests` (import + banned-API lint), proven to fail on `import AppKit` |
| Docs lag (`NEEDS.md` "never compiled" beside built apps) | docs carry `## Drift`; claims cite a command that re-derives them |
| Python generator writing Swift | no generated source; rules are data read at runtime |

## Drift
- None yet. The macOS app, gates and adapters are *planned*, not built; do not read them as present.
