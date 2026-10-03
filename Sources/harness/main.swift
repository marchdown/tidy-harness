import Foundation
import HarnessCore

// harness lens [sessions-dir] [--spec spec/doctrine.json] [--json]
// Reads every *.jsonl under the directory, folds each through the lens, prints the summary.
// Exit codes: 0 ok; 2 usage or unreadable spec; 3 some log lines were not records (reported on stderr, never hidden).

func fail(_ msg: String, _ code: Int32) -> Never {
    FileHandle.standardError.write(Data((msg + "\n").utf8))
    exit(code)
}

var args = Array(CommandLine.arguments.dropFirst())
guard args.first == "lens" else { fail("usage: harness lens [sessions-dir] [--spec spec/doctrine.json] [--json]", 2) }
args.removeFirst()

@MainActor func value(of flag: String) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    let v = args[i + 1]
    args.removeSubrange(i...(i + 1))
    return v
}
let specPath = value(of: "--spec") ?? "spec/doctrine.json"
let asJSON = args.contains("--json"); args.removeAll { $0 == "--json" }
let dirPath = args.first ?? (NSHomeDirectory() + "/.pi/agent/sessions")

let doctrine: Doctrine
do { doctrine = try Doctrine.decode(try Data(contentsOf: URL(fileURLWithPath: specPath))) }
catch { fail("cannot load spec \(specPath): \(error)", 2) }

guard let walker = FileManager.default.enumerator(at: URL(fileURLWithPath: dirPath), includingPropertiesForKeys: nil) else {
    fail("cannot read directory \(dirPath)", 2)
}
var files: [URL] = []
for case let u as URL in walker where u.pathExtension == "jsonl" { files.append(u) }
files.sort { $0.path < $1.path }

var facts: [Facts] = []
var unparsedTotal = 0
for u in files {
    guard let text = try? String(contentsOf: u, encoding: .utf8) else { fail("cannot read \(u.path)", 2) }
    let (records, unparsed) = PiLog.parse(text: text)
    unparsedTotal += unparsed
    facts.append(Lens.analyse(records: records, file: u.path, doctrine: doctrine))
}
let summary = Summary(facts: facts)
if asJSON { print(String(decoding: try summary.json(), as: UTF8.self)) } else { print(summary.render()) }
if unparsedTotal > 0 { FileHandle.standardError.write(Data("note: \(unparsedTotal) log line(s) were not records and were not counted\n".utf8)); exit(3) }
