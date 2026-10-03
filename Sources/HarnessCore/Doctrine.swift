import Foundation

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

    public enum SpecError: Error, Equatable { case badPattern(String), unsupportedVersion(Int) }

    public static func decode(_ data: Data) throws -> Doctrine {
        let d = try JSONDecoder().decode(Doctrine.self, from: data)
        guard d.version == 1 else { throw SpecError.unsupportedVersion(d.version) }
        // a pattern that does not compile is an error at load time, not a silent "never matches" later
        for p in [d.networkPattern, d.timeoutGuardPattern] {
            if (try? NSRegularExpression(pattern: p)) == nil { throw SpecError.badPattern(p) }
        }
        return d
    }

    /// `Verified:\W*(edited|compiled|tested|deployed)`, built from the data.
    var verifiedLevelPattern: String {
        NSRegularExpression.escapedPattern(for: markers.verified) + "\\W*(" + levels.joined(separator: "|") + ")"
    }
}
