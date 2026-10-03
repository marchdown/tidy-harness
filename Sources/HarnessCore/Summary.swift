import Foundation

/// The compact, machine-comparable result. The structure and key names are the CONFORMANCE CONTRACT:
/// every implementation must produce exactly this from the same logs (see ./conform.sh).
public struct Summary: Codable, Equatable, Sendable {
    public struct Totals: Codable, Equatable, Sendable { public var turns, errStops, results, resultErrs: Int }
    public struct PerModel: Codable, Equatable, Sendable { public var sessions, turns, errStops, results, resultErrs: Int }
    public struct Gate: Codable, Equatable, Sendable { public var on: [Int]; public var off: [Int] }
    public struct Rules: Codable, Equatable, Sendable { public var real: [String: [Int]]; public var probe: [String: [Int]] }

    public var sessions: Int
    public var real: Int
    public var probe: Int
    public var rules: Rules
    public var gate: Gate
    public var totals: Totals
    public var perModel: [String: PerModel]

    public static let ruleNames = [
        "done-when-before-first-mutation", "verified-line-at-end",
        "tested-claim-has-run-after-edit", "edits-read-first",
    ]

    /// [passed, applicable] over a rule that may not apply (nil).
    static func rate(_ fs: [Facts], _ kp: KeyPath<Facts, Bool?>) -> [Int] {
        let vs = fs.compactMap { $0[keyPath: kp] }
        return [vs.filter { $0 }.count, vs.count]
    }

    public init(facts: [Facts]) {
        func ruleMap(_ fs: [Facts]) -> [String: [Int]] {
            [
                "network-cmds-have-a-timeout": [fs.map(\.networkGuarded).reduce(0, +), fs.map(\.networkTotal).reduce(0, +)],
                "done-when-before-first-mutation": Summary.rate(fs, \.doneWhenBeforeFirstMutation),
                "verified-line-at-end": Summary.rate(fs, \.verifiedLineAtEnd),
                "tested-claim-has-run-after-edit": Summary.rate(fs, \.testedClaimHasRunAfterEdit),
                "edits-read-first": Summary.rate(fs, \.editsReadFirst),
            ]
        }
        let reals = facts.filter { $0.kind == .real }, probes = facts.filter { $0.kind == .probe }
        sessions = facts.count; real = reals.count; probe = probes.count
        rules = Rules(real: ruleMap(reals), probe: ruleMap(probes))
        gate = Gate(on: Summary.rate(reals.filter { $0.gated }, \.doneWhenBeforeFirstMutation),
                    off: Summary.rate(reals.filter { !$0.gated }, \.doneWhenBeforeFirstMutation))
        totals = Totals(turns: facts.map(\.assistantTurns).reduce(0, +), errStops: facts.map(\.errStops).reduce(0, +),
                        results: facts.map(\.results).reduce(0, +), resultErrs: facts.map(\.resultErrs).reduce(0, +))
        var pm: [String: PerModel] = [:]
        for f in facts {
            for (model, s) in f.perModel {
                var p = pm[model] ?? PerModel(sessions: 0, turns: 0, errStops: 0, results: 0, resultErrs: 0)
                p.sessions += 1; p.turns += s.turns; p.errStops += s.errStops; p.results += s.results; p.resultErrs += s.resultErrs
                pm[model] = p
            }
        }
        perModel = pm
    }

    public func json() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try e.encode(self)
    }

    private func pct(_ a: Int, _ b: Int) -> String { b == 0 ? "  n/a" : String(format: "%3d%%", Int((100.0 * Double(a) / Double(b)).rounded(.down))) }

    public func render() -> String {
        var o: [String] = ["SUMMARY  \(sessions) sessions (\(real) real, \(probe) probe)"]
        for (label, m) in [("real", rules.real), ("probe", rules.probe)] {
            o.append("  \(label)")
            for n in Summary.ruleNames + ["network-cmds-have-a-timeout"] {
                let v = m[n] ?? [0, 0]
                o.append("    \(n.padding(toLength: 36, withPad: " ", startingAt: 0)) \(v[0])/\(v[1]) \(pct(v[0], v[1]))")
            }
        }
        o.append("  done-when by gate: ON \(gate.on[0])/\(gate.on[1]) \(pct(gate.on[0], gate.on[1]))   off \(gate.off[0])/\(gate.off[1]) \(pct(gate.off[0], gate.off[1]))")
        o.append("  totals: turns \(totals.turns), error stops \(totals.errStops) (\(pct(totals.errStops, totals.turns))), tool results \(totals.results), tool errors \(totals.resultErrs) (\(pct(totals.resultErrs, totals.results)))")
        o.append("  per model                              sessions  turns  err-stops")
        for (m, p) in perModel.sorted(by: { $0.value.turns > $1.value.turns }) {
            o.append("    \(m.padding(toLength: 38, withPad: " ", startingAt: 0)) \(p.sessions)  \(p.turns)  \(p.errStops) (\(pct(p.errStops, p.turns)))")
        }
        return o.joined(separator: "\n")
    }
}
