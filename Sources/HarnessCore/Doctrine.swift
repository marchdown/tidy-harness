import Foundation

/// One doctrine rule in the catalog: where it comes from, and every sensor that measures or enforces it.
public struct Rule: Sendable, Equatable, Decodable {
    public var id: String
    public var source: String
    /// The summary key of the lens predicate that measures it in real logs (nil = not measured in logs).
    public var lens: String?
    /// Ids of controlled probes (~/pi-harness/eval/probes.edn) that test it.
    public var probes: [String]
    /// The gate that enforces it, and whether that gate exists yet.
    public var gate: String?
    public var gateStatus: String?

    public var sensors: [String] {
        var s: [String] = []
        if lens != nil { s.append("lens") }
        if !probes.isEmpty { s.append("probe") }
        if gate != nil { s.append("gate") }
        return s
    }
}

/// The doctrine rules as data (spec/doctrine.json). The core never hardcodes a pattern: it is handed these.
public struct Doctrine: Sendable, Equatable, Decodable {
    public struct Markers: Sendable, Equatable, Decodable {
        public var doneWhen: String
        public var gatePhase: String
        public var verified: String
    }
    public var version: Int
    public var markers: Markers
    public var levels: [String]
    public var claimLevelsNeedingARun: [String]
    public var mutatingTools: [String]
    public var networkPattern: String
    public var timeoutGuardPattern: String
    public var probeCwdPrefix: String
    public var rules: [Rule]

    public enum SpecError: Error, Equatable {
        case badPattern(String)
        case unsupportedVersion(Int)
        case duplicateRule(String)
        case unsourcedRule(String)      // a rule must say where it comes from
        case unmeasuredRule(String)     // a rule nobody measures or enforces is folklore
        case unknownLens(rule: String, lens: String)
    }

    private enum CodingKeys: String, CodingKey {
        case version, markers, levels, claimLevelsNeedingARun, mutatingTools, networkPattern,
             timeoutGuardPattern, probeCwdPrefix, rules
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        markers = try c.decode(Markers.self, forKey: .markers)
        levels = try c.decode([String].self, forKey: .levels)
        claimLevelsNeedingARun = try c.decode([String].self, forKey: .claimLevelsNeedingARun)
        mutatingTools = try c.decode([String].self, forKey: .mutatingTools)
        networkPattern = try c.decode(String.self, forKey: .networkPattern)
        timeoutGuardPattern = try c.decode(String.self, forKey: .timeoutGuardPattern)
        probeCwdPrefix = try c.decode(String.self, forKey: .probeCwdPrefix)
        rules = try c.decodeIfPresent([Rule].self, forKey: .rules) ?? []
    }

    /// The summary keys a catalog rule may name as its lens predicate.
    public static let knownLenses: Set<String> = Set(Summary.ruleNames + ["network-cmds-have-a-timeout", "perModel"])

    public static func decode(_ data: Data) throws -> Doctrine {
        let d = try JSONDecoder().decode(Doctrine.self, from: data)
        guard d.version == 1 else { throw SpecError.unsupportedVersion(d.version) }
        // a pattern that does not compile is an error at load time, not a silent "never matches" later
        for p in [d.networkPattern, d.timeoutGuardPattern] {
            if (try? NSRegularExpression(pattern: p)) == nil { throw SpecError.badPattern(p) }
        }
        var seen = Set<String>()
        for r in d.rules {
            guard seen.insert(r.id).inserted else { throw SpecError.duplicateRule(r.id) }
            guard !r.source.trimmingCharacters(in: .whitespaces).isEmpty else { throw SpecError.unsourcedRule(r.id) }
            guard !r.sensors.isEmpty else { throw SpecError.unmeasuredRule(r.id) }
            if let l = r.lens, !knownLenses.contains(l) { throw SpecError.unknownLens(rule: r.id, lens: l) }
        }
        return d
    }

    /// `Verified:\W*(edited|compiled|tested|deployed)`, built from the data.
    var verifiedLevelPattern: String {
        NSRegularExpression.escapedPattern(for: markers.verified) + "\\W*(" + levels.joined(separator: "|") + ")"
    }

    /// Lens predicates that no catalog rule claims: a measurement with no stated purpose.
    public var orphanLenses: [String] {
        let claimed = Set(rules.compactMap(\.lens))
        return Doctrine.knownLenses.subtracting(claimed).sorted()
    }

    /// A text matrix: which rules are measured, probed and enforced, and where the gaps are.
    public func renderCatalog() -> String {
        let w = (rules.map(\.id.count).max() ?? 4) + 2
        func col(_ s: String, _ n: Int) -> String { s.padding(toLength: n, withPad: " ", startingAt: 0) }
        var o = [col("rule", w) + col("lens", 8) + col("probe", 8) + "gate"]
        for r in rules {
            let gate = r.gate.map { "\($0) (\(r.gateStatus ?? "?"))" } ?? "-"
            o.append(col(r.id, w) + col(r.lens == nil ? "-" : "yes", 8) + col(r.probes.isEmpty ? "-" : String(r.probes.count), 8) + gate)
        }
        let noLens = rules.filter { $0.lens == nil }.map(\.id), noProbe = rules.filter { $0.probes.isEmpty }.map(\.id)
        o.append("")
        o.append("measured in real logs but never probed: " + (noProbe.isEmpty ? "none" : noProbe.joined(separator: ", ")))
        o.append("probed but not measured in real logs:   " + (noLens.isEmpty ? "none" : noLens.joined(separator: ", ")))
        let orphans = orphanLenses
        if !orphans.isEmpty { o.append("lens predicates with no catalog rule: " + orphans.joined(separator: ", ")) }
        return o.joined(separator: "\n")
    }
}
