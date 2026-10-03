import Foundation

// The canonical log is the pi session format (JSON Lines). One record per line. This file normalises
// the few fields the harness reasons about and is deliberately tolerant: unknown record types and
// unknown fields are kept out of the way, never fatal. A log line we cannot read is `nil`, and callers
// count it — they do not drop it silently.

public struct ToolCall: Sendable, Equatable {
    public var name: String
    public var path: String?
    public var command: String?
    /// True when the call carried an explicit `timeout` argument.
    public var hasTimeout: Bool

    public init(name: String, path: String? = nil, command: String? = nil, hasTimeout: Bool = false) {
        self.name = name; self.path = path; self.command = command; self.hasTimeout = hasTimeout
    }
}

public struct Message: Sendable, Equatable {
    public var role: String
    /// Text blocks joined by "\n", or the content itself when it is a plain string.
    public var text: String
    public var model: String?
    public var stopReason: String?
    public var calls: [ToolCall]
    public var isError: Bool

    public init(role: String, text: String = "", model: String? = nil, stopReason: String? = nil,
                calls: [ToolCall] = [], isError: Bool = false) {
        self.role = role; self.text = text; self.model = model; self.stopReason = stopReason
        self.calls = calls; self.isError = isError
    }
}

public struct Record: Sendable, Equatable {
    public var type: String
    public var cwd: String?
    public var message: Message?

    public init(type: String, cwd: String? = nil, message: Message? = nil) {
        self.type = type; self.cwd = cwd; self.message = message
    }
}

public enum PiLog {
    /// Parse one JSON line. Returns nil for anything that is not a JSON object with a string `type`.
    public static func parse(line: String) -> Record? {
        guard let data = line.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = obj["type"] as? String else { return nil }
        var rec = Record(type: type, cwd: obj["cwd"] as? String)
        if type == "message", let m = obj["message"] as? [String: Any] {
            rec.message = message(from: m)
        }
        return rec
    }

    static func message(from m: [String: Any]) -> Message {
        var text = ""
        var calls: [ToolCall] = []
        if let s = m["content"] as? String {
            text = s
        } else if let blocks = m["content"] as? [[String: Any]] {
            var parts: [String] = []
            for b in blocks {
                switch b["type"] as? String {
                case "text":
                    if let t = b["text"] as? String { parts.append(t) }
                case "toolCall":
                    let args = b["arguments"] as? [String: Any] ?? [:]
                    let hasTimeout = args["timeout"] != nil && !(args["timeout"] is NSNull)
                    calls.append(ToolCall(name: b["name"] as? String ?? "",
                                          path: args["path"] as? String,
                                          command: args["command"] as? String,
                                          hasTimeout: hasTimeout))
                default: break
                }
            }
            text = parts.joined(separator: "\n")
        }
        return Message(role: m["role"] as? String ?? "", text: text,
                       model: m["model"] as? String, stopReason: m["stopReason"] as? String,
                       calls: calls, isError: (m["isError"] as? Bool) ?? false)
    }

    /// Parse a whole log. `unparsed` counts non-empty lines that were not records: reported, never hidden.
    public static func parse(text: String) -> (records: [Record], unparsed: Int) {
        var records: [Record] = []
        var unparsed = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if let r = parse(line: String(line)) { records.append(r) } else { unparsed += 1 }
        }
        return (records, unparsed)
    }
}
