import Testing
import Foundation
@testable import HarnessCore

// The doctrine used by every test is the real shared spec, not a copy: if the spec changes, these run against it.
let doctrine: Doctrine = {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let data = try! Data(contentsOf: root.appendingPathComponent("spec/doctrine.json"))
    return try! Doctrine.decode(data)
}()

func asst(_ text: String = "", model: String? = "m1", calls: [ToolCall] = [], stop: String? = nil) -> Record {
    Record(type: "message", message: Message(role: "assistant", text: text, model: model, stopReason: stop, calls: calls))
}
func user(_ text: String) -> Record { Record(type: "message", message: Message(role: "user", text: text)) }
func result(isError: Bool = false) -> Record { Record(type: "message", message: Message(role: "toolResult", isError: isError)) }
func session(_ cwd: String) -> Record { Record(type: "session", cwd: cwd) }
func edit(_ p: String) -> ToolCall { ToolCall(name: "edit", path: p) }
func write(_ p: String) -> ToolCall { ToolCall(name: "write", path: p) }
func read(_ p: String) -> ToolCall { ToolCall(name: "read", path: p) }
func bash(_ c: String, timeout: Bool = false) -> ToolCall { ToolCall(name: "bash", command: c, hasTimeout: timeout) }
func analyse(_ rs: [Record]) -> Facts { Lens.analyse(records: rs, file: "t.jsonl", doctrine: doctrine) }

@Suite("Parsing is tolerant, and never silent about what it could not read")
struct ParsingTests {
    @Test func nonRecordsAreNilAndCounted() {
        #expect(PiLog.parse(line: "not json") == nil)
        #expect(PiLog.parse(line: "[1,2]") == nil)
        #expect(PiLog.parse(line: #"{"no":"type"}"#) == nil)
        let (recs, unparsed) = PiLog.parse(text: "{\"type\":\"session\",\"cwd\":\"/x\"}\ngarbage\n\n{\"type\":\"other\"}\n")
        #expect(recs.count == 2)
        #expect(unparsed == 1)      // the blank line is not a failure; the garbage line is
    }

    @Test func messageContentMayBeAStringOrBlocks() {
        let s = PiLog.parse(line: #"{"type":"message","message":{"role":"user","content":"hello"}}"#)
        #expect(s?.message?.text == "hello")
        let b = PiLog.parse(line: #"""
        {"type":"message","message":{"role":"assistant","model":"m","stopReason":"toolUse","content":[
          {"type":"text","text":"one"},{"type":"thinking","thinking":"hmm"},{"type":"text","text":"two"},
          {"type":"toolCall","name":"bash","arguments":{"command":"curl x","timeout":30}},
          {"type":"toolCall","name":"edit","arguments":{"path":"/a","edits":[]}}]}}
        """#)
        #expect(b?.message?.text == "one\ntwo")
        #expect(b?.message?.calls.count == 2)
        #expect(b?.message?.calls[0].hasTimeout == true)
        #expect(b?.message?.calls[1].path == "/a")
        #expect(b?.message?.model == "m")
    }

    @Test func nullTimeoutIsNotATimeout() {
        let r = PiLog.parse(line: #"{"type":"message","message":{"role":"assistant","content":[{"type":"toolCall","name":"bash","arguments":{"command":"ls","timeout":null}}]}}"#)
        #expect(r?.message?.calls.first?.hasTimeout == false)
    }
}

@Suite("Each doctrine rule, stated as a predicate over the ordered transcript")
struct RuleTests {
    @Test func doneWhenMustComeInAnEarlierMessageThanTheFirstMutation() {
        #expect(analyse([asst("Done when: tests pass"), asst(calls: [edit("a")])]).doneWhenBeforeFirstMutation == true)
        // same message as the mutation does not count — the line must be stated BEFORE acting
        #expect(analyse([asst("Done when: x", calls: [write("a")])]).doneWhenBeforeFirstMutation == false)
        #expect(analyse([asst(calls: [write("a")])]).doneWhenBeforeFirstMutation == false)
        // no mutation at all: the rule did not apply (nil), which is not a pass
        #expect(analyse([asst("Done when: x"), asst(calls: [bash("ls")])]).doneWhenBeforeFirstMutation == nil)
    }

    @Test func verifiedLineMustNameAKnownLevelNearTheEnd() {
        #expect(analyse([asst(calls: [write("a")]), asst("Verified: tested with cargo test")]).verifiedLineAtEnd == true)
        #expect(analyse([asst(calls: [write("a")]), asst("Verified: yes it works")]).verifiedLineAtEnd == false)   // marker without a level
        #expect(analyse([asst(calls: [write("a")]), asst("all done")]).verifiedLineAtEnd == false)
        #expect(analyse([asst("Verified: tested")]).verifiedLineAtEnd == nil)                                       // no mutation: n/a
    }

    @Test func aTestedClaimNeedsABashRunAfterTheLastMutation() {
        let ok = analyse([asst(calls: [edit("a")]), asst(calls: [bash("cargo test")]), asst("Verified: tested")])
        #expect(ok.testedClaimHasRunAfterEdit == true)
        let stale = analyse([asst(calls: [bash("cargo test")]), asst(calls: [edit("a")]), asst("Verified: tested")])
        #expect(stale.testedClaimHasRunAfterEdit == false)   // the run happened BEFORE the final edit
        #expect(analyse([asst(calls: [edit("a")]), asst("Verified: edited")]).testedClaimHasRunAfterEdit == nil)  // weak claim: no run needed
    }

    @Test func editsMustTargetPathsAlreadySeen() {
        #expect(analyse([asst(calls: [read("a"), edit("a")])]).editsReadFirst == true)
        #expect(analyse([asst(calls: [write("a")]), asst(calls: [edit("a")])]).editsReadFirst == true)
        #expect(analyse([asst(calls: [edit("a")])]).editsReadFirst == false)
        #expect(analyse([asst(calls: [read("a"), edit("a"), edit("b")])]).editsReadFirst == false)
        #expect(analyse([asst(calls: [read("a")])]).editsReadFirst == nil)
    }

    @Test func networkCommandsNeedATimeoutByArgumentOrInTheCommand() {
        let f = analyse([asst(calls: [
            bash("curl https://x"),                    // network, unguarded
            bash("curl https://x", timeout: true),     // guarded by argument
            bash("timeout 5 curl https://x"),          // guarded in the command line
            bash("ssh -o ConnectTimeout=8 host true"), // guarded by option
            bash("git push origin main"),              // network, unguarded
            bash("ls -la"),                            // not network
        ])])
        #expect(f.networkTotal == 5)
        #expect(f.networkGuarded == 3)
    }
}

@Suite("Counting turns, errors and models")
struct CountingTests {
    @Test func everyAssistantMessageIsATurnEvenIfItOnlyErrored() {
        let f = analyse([asst("hi"), asst(model: "bad", stop: "error"), asst(model: "bad", stop: "error")])
        #expect(f.assistantTurns == 3)
        #expect(f.errStops == 2)
        #expect(f.perModel["bad"]?.turns == 2)
        #expect(f.perModel["bad"]?.errStops == 2)
        #expect(f.perModel["m1"]?.turns == 1)
    }

    @Test func toolResultsAreAttributedToTheModelThatMadeTheCall() {
        let f = analyse([asst(model: "a", calls: [bash("ls")]), result(isError: true), asst(model: "b", calls: [bash("ls")]), result()])
        #expect(f.perModel["a"]?.results == 1)
        #expect(f.perModel["a"]?.resultErrs == 1)
        #expect(f.perModel["b"]?.results == 1)
        #expect(f.perModel["b"]?.resultErrs == 0)
    }

    @Test func gateAndProbeAreDetectedMechanically() {
        #expect(analyse([user("do it\n\n[Phase 1 of 2 — tools are locked until you answer.]")]).gated == true)
        #expect(analyse([user("do it")]).gated == false)
        #expect(analyse([session("/private/tmp/pi-eval/x")]).kind == .probe)
        #expect(analyse([session("/Users/me/proj")]).kind == .real)
    }

    @Test func notApplicableIsNeverCountedAsAPass() {
        let nothing = Facts(file: "t", kind: .real, gated: false)          // every rule nil
        let s = Summary(facts: [nothing])
        #expect(s.rules.real["verified-line-at-end"] == [0, 0])
        #expect(s.gate.on == [0, 0] && s.gate.off == [0, 0])
    }
}

@Suite("The spec is data that must be valid")
struct SpecTests {
    @Test func aBadPatternFailsAtLoadTimeNotSilentlyLater() {
        let bad = #"{"version":1,"markers":{"doneWhen":"a","gatePhase":"b","verified":"c"},"levels":["x"],"claimLevelsNeedingARun":[],"mutatingTools":[],"networkPattern":"(","timeoutGuardPattern":"x","probeCwdPrefix":"/"}"#
        #expect(throws: Doctrine.SpecError.self) { try Doctrine.decode(Data(bad.utf8)) }
    }
    @Test func anUnknownVersionIsRefused() {
        let v2 = #"{"version":2,"markers":{"doneWhen":"a","gatePhase":"b","verified":"c"},"levels":["x"],"claimLevelsNeedingARun":[],"mutatingTools":[],"networkPattern":"a","timeoutGuardPattern":"x","probeCwdPrefix":"/"}"#
        #expect(throws: Doctrine.SpecError.unsupportedVersion(2)) { try Doctrine.decode(Data(v2.utf8)) }
    }
}

@Suite("Purity: a rule a machine can check, a machine checks")
struct PurityTests {
    @Test func coreImportsFoundationAndNothingElse() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let dir = root.appendingPathComponent("Sources/HarnessCore")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).filter { $0.pathExtension == "swift" }
        #expect(files.count >= 4)
        for f in files {
            let text = try String(contentsOf: f, encoding: .utf8)
            for line in text.split(separator: "\n") where line.hasPrefix("import ") {
                #expect(line == "import Foundation", "\(f.lastPathComponent) imports more than Foundation: \(line)")
            }
            // no clock, no randomness, no file or process access: the core is deterministic
            for banned in ["Date()", "Process(", "FileManager", "URLSession", "SystemRandomNumberGenerator", ".random("] {
                #expect(!text.contains(banned), "\(f.lastPathComponent) uses \(banned): the core must stay pure")
            }
        }
    }
}

@Suite("The rule catalog ties doctrine text to its sensors")
struct CatalogTests {
    private func spec(rules: String) -> Data {
        Data(#"{"version":1,"markers":{"doneWhen":"a","gatePhase":"b","verified":"c"},"levels":["x"],"claimLevelsNeedingARun":[],"mutatingTools":[],"networkPattern":"a","timeoutGuardPattern":"x","probeCwdPrefix":"/","rules":\#(rules)}"#.utf8)
    }

    @Test func everyLensPredicateIsClaimedByARule() {
        // a measurement with no stated purpose is noise: the real catalog must claim all of them
        #expect(doctrine.orphanLenses.isEmpty, "unclaimed lens predicates: \(doctrine.orphanLenses)")
    }

    @Test func everyRuleHasASourceAndASensor() {
        #expect(doctrine.rules.count >= 10)
        for r in doctrine.rules {
            #expect(!r.source.isEmpty, "\(r.id) has no source")
            #expect(!r.sensors.isEmpty, "\(r.id) has no sensor")
        }
        #expect(Set(doctrine.rules.map(\.id)).count == doctrine.rules.count)
    }

    @Test func aRuleNobodyMeasuresIsRefusedAtLoad() {
        #expect(throws: Doctrine.SpecError.unmeasuredRule("r")) {
            try Doctrine.decode(spec(rules: #"[{"id":"r","source":"s","probes":[]}]"#))
        }
    }
    @Test func aRuleWithoutASourceIsRefused() {
        #expect(throws: Doctrine.SpecError.unsourcedRule("r")) {
            try Doctrine.decode(spec(rules: #"[{"id":"r","source":" ","probes":["p"]}]"#))
        }
    }
    @Test func duplicateIdsAndUnknownLensesAreRefused() {
        #expect(throws: Doctrine.SpecError.duplicateRule("r")) {
            try Doctrine.decode(spec(rules: #"[{"id":"r","source":"s","probes":["p"]},{"id":"r","source":"s","probes":["p"]}]"#))
        }
        #expect(throws: Doctrine.SpecError.unknownLens(rule: "r", lens: "nope")) {
            try Doctrine.decode(spec(rules: #"[{"id":"r","source":"s","lens":"nope","probes":[]}]"#))
        }
    }
    @Test func catalogRendersTheGaps() {
        let text = doctrine.renderCatalog()
        #expect(text.contains("measured in real logs but never probed:"))
        #expect(text.contains("read-before-overwrite"))     // lens-only today
        #expect(text.contains("no-python-node"))            // probe-only today
    }
}
