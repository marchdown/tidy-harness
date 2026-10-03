import Foundation

// The deterministic lens: a fold over a session log that says what the agent actually did,
// without asking it. Rules are predicates over the ordered transcript. Each is `true`, `false`,
// or `nil` — and nil means "did not apply", which is not the same as passing.

public enum SessionKind: String, Sendable, Equatable { case real, probe }

public struct ModelStats: Sendable, Equatable {
    public var turns = 0       // assistant MESSAGES — the denominator for every rate
    public var errStops = 0    // assistant messages that ended with stopReason == "error"
    public var results = 0
    public var resultErrs = 0
    public init() {}
}

public struct Facts: Sendable, Equatable {
    public var file: String
    public var kind: SessionKind
    public var gated: Bool
    public var assistantTurns = 0
    public var errStops = 0
    public var results = 0
    public var resultErrs = 0
    public var perModel: [String: ModelStats] = [:]
    public var doneWhenBeforeFirstMutation: Bool?
    public var verifiedLineAtEnd: Bool?
    public var testedClaimHasRunAfterEdit: Bool?
    public var editsReadFirst: Bool?
    public var networkTotal = 0
    public var networkGuarded = 0

    public init(file: String, kind: SessionKind, gated: Bool) {
        self.file = file; self.kind = kind; self.gated = gated
    }
}

public enum Lens {
    // Internal ordered event, indexed by MESSAGE position (so "before" and "after" are well defined).
    private enum Ev {
        case assistant
        case text(String)
        case call(ToolCall)
        case errStop
        case result(isError: Bool)
    }
    private struct Tagged { var i: Int; var model: String?; var ev: Ev }

    public static func analyse(records: [Record], file: String, doctrine d: Doctrine) -> Facts {
        let cwd = records.first(where: { $0.type == "session" })?.cwd
        var tagged: [Tagged] = []
        var model: String? = nil
        var gated = false
        var i = 0
        for rec in records where rec.type == "message" {
            let m = rec.message ?? Message(role: "")
            switch m.role {
            case "assistant":
                model = m.model ?? model
                tagged.append(Tagged(i: i, model: model, ev: .assistant))
                if !m.text.isEmpty { tagged.append(Tagged(i: i, model: model, ev: .text(m.text))) }
                for c in m.calls { tagged.append(Tagged(i: i, model: model, ev: .call(c))) }
                if m.stopReason == "error" { tagged.append(Tagged(i: i, model: model, ev: .errStop)) }
            case "toolResult":
                tagged.append(Tagged(i: i, model: model, ev: .result(isError: m.isError)))
            case "user":
                // the done-when gate extension appends its Phase-1 prompt to the user message: a mechanical tell
                if m.text.contains(d.markers.gatePhase) { gated = true }
            default: break
            }
            i += 1
        }

        let kind: SessionKind = (cwd ?? "").hasPrefix(d.probeCwdPrefix) ? .probe : .real
        var f = Facts(file: file, kind: kind, gated: gated)

        // counters
        for t in tagged {
            let key = t.model ?? "?"
            switch t.ev {
            case .assistant: f.assistantTurns += 1; f.perModel[key, default: ModelStats()].turns += 1
            case .errStop: f.errStops += 1; f.perModel[key, default: ModelStats()].errStops += 1
            case .result(let isErr):
                f.results += 1; f.perModel[key, default: ModelStats()].results += 1
                if isErr { f.resultErrs += 1; f.perModel[key, default: ModelStats()].resultErrs += 1 }
            default: break
            }
        }

        let calls: [(i: Int, c: ToolCall)] = tagged.compactMap { if case .call(let c) = $0.ev { return ($0.i, c) } else { return nil } }
        let texts: [(i: Int, t: String)] = tagged.compactMap { if case .text(let s) = $0.ev { return ($0.i, s) } else { return nil } }
        let muts = calls.filter { d.mutatingTools.contains($0.c.name) }
        let firstMut = muts.first?.i, lastMut = muts.last?.i

        // 1. a Done-when line precedes the first mutation (strictly earlier message)
        if let fm = firstMut {
            f.doneWhenBeforeFirstMutation = texts.contains { $0.i < fm && $0.t.contains(d.markers.doneWhen) }
        }

        // 2. a Verified: line naming a level, in the last three texts
        let last3 = texts.suffix(3).map(\.t).joined(separator: "\n")
        var level: String? = nil
        if let re = try? NSRegularExpression(pattern: d.verifiedLevelPattern),
           let m = re.firstMatch(in: last3, range: NSRange(last3.startIndex..., in: last3)),
           m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: last3) {
            level = String(last3[r])
        }
        if !muts.isEmpty { f.verifiedLineAtEnd = (level != nil) }

        // 3. a "tested"/"deployed" claim is backed by a bash call after the last mutation
        let bash = calls.filter { $0.c.name == "bash" }
        if let l = level, d.claimLevelsNeedingARun.contains(l) {
            f.testedClaimHasRunAfterEdit = lastMut.map { lm in bash.contains { $0.i > lm } } ?? false
        }

        // 4. every edit targets a path already read, written or edited earlier in the session
        var seen = Set<String>()
        var checks: [Bool] = []
        for (_, c) in calls {
            guard let p = c.path, ["read", "write", "edit"].contains(c.name) else { continue }
            let ok = seen.contains(p)
            seen.insert(p)
            if c.name == "edit" { checks.append(ok) }
        }
        if !checks.isEmpty { f.editsReadFirst = checks.allSatisfy { $0 } }

        // 5. network commands carry a timeout (argument or in the command line)
        if let net = try? NSRegularExpression(pattern: d.networkPattern),
           let guardRe = try? NSRegularExpression(pattern: d.timeoutGuardPattern) {
            func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
                re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
            }
            for (_, c) in bash {
                let cmd = c.command ?? ""
                guard matches(net, cmd) else { continue }
                f.networkTotal += 1
                if c.hasTimeout || matches(guardRe, cmd) { f.networkGuarded += 1 }
            }
        }
        return f
    }
}
