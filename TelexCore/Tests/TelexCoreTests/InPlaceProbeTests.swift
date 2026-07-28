import XCTest
@testable import TelexCore

// The input controller edits text in place with insertText(_:replacementRange:).
// A compliant app REPLACES; some apps (Terminal, iTerm2's CJK IMKit path, Mac
// Catalyst like WhatsApp, Electron/CEF like Slack & Lark) ignore the range and
// APPEND at the caret, so tone edits pile up without replacing and diacritics never
// render.
//
// These tests drive the REAL TelexEngine and replay its actions through simulated
// clients — one honoring the range, one appending honestly, and one that appends
// but ECHOES its read-back (models Slack/Lark/iTerm) — then feed the exact caret +
// read-back to InPlaceProbe.verdict. They pin down that:
//   • the caret catches the append apps even when the read-back is echoed, and
//   • text read-back alone (the old signal) false-positives the echoing app —
//     the precise regression that silently broke iTerm2, then Slack & Lark.
final class InPlaceProbeTests: XCTestCase {

    private enum Mode { case honor, append, appendEcho }

    /// Simulated input client. NSString offsets match IMKit; every composed
    /// Vietnamese scalar is a single BMP UTF-16 unit, so offsets line up 1:1.
    private final class Client {
        let mode: Mode
        let doc = NSMutableString()
        var caret = 0
        init(_ mode: Mode) { self.mode = mode }
        func insert(_ s: String, at loc: Int, length bs: Int) {
            if mode == .honor {
                doc.replaceCharacters(in: NSRange(location: loc, length: bs), with: s)
                caret = loc + (s as NSString).length
            } else {
                doc.insert(s, at: caret)             // ignores range → append at caret
                caret += (s as NSString).length
            }
        }
        /// Read-back for [loc, loc+len). An echoing app pretends it holds `inserted`
        /// there regardless of what actually happened.
        func readback(at loc: Int, length len: Int, echo: String) -> String? {
            if mode == .appendEcho { return echo }
            guard loc >= 0, len >= 0, loc + len <= doc.length else { return nil }
            return doc.substring(with: NSRange(location: loc, length: len))
        }
    }

    private struct Probe {
        let start: Int, bs: Int, insLen: Int, inserted: String
        let caret: Int
        let region: String?
    }

    /// Replay the controller's tracking in-place applier over `keys` against a client
    /// in `mode`, returning the first probe-eligible replace + that client's caret
    /// and target-region read-back at that instant.
    private func firstProbe(_ keys: String, _ mode: Mode) -> Probe? {
        var e = TelexEngine(); e.liveSpellCheck = true; e.simpleTelex = true
        let c = Client(mode)
        var onLen = 0
        for ch in keys {
            switch e.feed(ch) {
            case .passthrough:
                let s = String(ch)
                c.insert(s, at: onLen, length: 0)
                onLen += (s as NSString).length
            case let .replace(bs, insert):
                let start = onLen - bs
                c.insert(insert, at: start, length: bs)
                let insLen = (insert as NSString).length
                onLen += insLen - bs
                if InPlaceProbe.shouldProbe(insertLength: insLen, bs: bs, clear: 0, needsProbe: true) {
                    return Probe(start: start, bs: bs, insLen: insLen, inserted: insert,
                                 caret: c.caret,
                                 region: c.readback(at: start, length: insLen, echo: insert))
                }
            case .none:
                break
            }
        }
        return nil
    }

    private func verdict(_ p: Probe) -> InPlaceProbe.Verdict {
        InPlaceProbe.verdict(axRegion: nil, caret: p.caret, start: p.start, bs: p.bs,
                             insertLength: p.insLen, regionReadback: p.region, inserted: p.inserted)
    }

    // Telex sequences whose first modifier/tone key is a real replace.
    private let cases = [
        "cas", "caf", "awn", "cowm", "thuw", "ddi", "gox", "maj",
        "vieejt", "truowngf", "hoas", "nguoiwf", "dduowngf", "quaf",
    ]

    func testCompliantAppStaysInPlace() {
        for keys in cases {
            guard let p = firstProbe(keys, .honor) else { XCTFail("no probe: \(keys)"); continue }
            XCTAssertEqual(verdict(p), .honored, "compliant app should be honored: \(keys)")
        }
    }

    func testHonestAppendAppDetected() {
        for keys in cases {
            guard let p = firstProbe(keys, .append) else { XCTFail("no probe: \(keys)"); continue }
            XCTAssertEqual(verdict(p), .appended, "honest append app must be caught: \(keys)")
        }
    }

    func testEchoingAppendAppStillDetectedByCaret() {
        // Slack/Lark/iTerm: append AND echo the read-back. The caret (start+bs+len)
        // still exposes the append even though the region read-back returns `inserted`.
        for keys in cases {
            guard let p = firstProbe(keys, .appendEcho) else { XCTFail("no probe: \(keys)"); continue }
            XCTAssertEqual(p.region, p.inserted, "sanity: echo client returns inserted")
            XCTAssertEqual(verdict(p), .appended, "echoing append app must be caught by caret: \(keys)")
        }
    }

    func testTextReadbackAloneWouldFalsePositiveEchoingApp() {
        // Documents WHY caret is needed: with no caret, the echoed read-back looks
        // honored — the exact false-positive that broke Slack & Lark.
        for keys in cases {
            guard let p = firstProbe(keys, .appendEcho) else { XCTFail("no probe: \(keys)"); continue }
            let readbackOnly = InPlaceProbe.verdict(axRegion: nil, caret: nil, start: p.start, bs: p.bs,
                                                    insertLength: p.insLen, regionReadback: p.region,
                                                    inserted: p.inserted)
            XCTAssertEqual(readbackOnly, .honored, "read-back alone false-positives the echo app: \(keys)")
        }
    }

    func testSafeFallbackToMarkedTextWhenUnconfirmed() {
        // Safety-first: only a caret at start+len keeps in-place; everything else →
        // marked text, which always renders Vietnamese (this is the behavior the app
        // relied on when Accessibility was missing: it worked, just with an underline).
        // No evidence at all → marked text (never silently break in-place).
        XCTAssertEqual(InPlaceProbe.verdict(axRegion: nil, caret: nil, start: 2, bs: 1, insertLength: 1,
                                            regionReadback: nil, inserted: "ê"), .appended)
        // Caret present but not the clean-replace position (untrusted) → marked text,
        // EVEN IF the read-back is echoed to match. Silently dropping diacritics is
        // worse than a cosmetic underline.
        XCTAssertEqual(InPlaceProbe.verdict(axRegion: nil, caret: 999, start: 2, bs: 1, insertLength: 1,
                                            regionReadback: "ê", inserted: "ê"), .appended)
        // No caret, but a positive read-back match → trust it and keep in-place.
        XCTAssertEqual(InPlaceProbe.verdict(axRegion: nil, caret: nil, start: 2, bs: 1, insertLength: 1,
                                            regionReadback: "ê", inserted: "ê"), .honored)
    }

    // A caret BEHIND the replace position is IMPOSSIBLE for either outcome (replace →
    // start+len, append → start+bs+len, which is further RIGHT), so it is a stale /
    // foreign-coordinate report and must teach the classifier nothing. Tester logs
    // 2026-07-27: Jira in Chrome answered caret=1338 for expectedReplace=1340, and Google
    // Sheets answered caret=2 for expectedReplace=3 (one edit behind) — the AX tree
    // confirmed BOTH replaces landed. Reading those as "appended" demoted healthy fields
    // to marked text: Jira mangled text mid-word, and a not-yet-editing Sheets cell
    // ignores marked text entirely, so nothing typed appeared until the cell was
    // double-clicked (issue #31).
    func testCaretBehindTheReplacePositionIsInconclusive() {
        XCTAssertEqual(InPlaceProbe.verdict(axRegion: nil, caret: 1338, start: 1339, bs: 1,
                                            insertLength: 1, regionReadback: nil,
                                            inserted: "ậ"), .inconclusive)
        XCTAssertEqual(InPlaceProbe.verdict(axRegion: nil, caret: 0, start: 2, bs: 1,
                                            insertLength: 1, regionReadback: nil,
                                            inserted: "ê"), .inconclusive)
        // The window is narrow: a CONSTANT garbage caret (Lark answers 1 forever) is far
        // behind the anchor mid-field, so it stays real evidence and still demotes.
        XCTAssertEqual(InPlaceProbe.verdict(axRegion: nil, caret: 1, start: 29, bs: 1,
                                            insertLength: 1, regionReadback: nil,
                                            inserted: "á"), .appended)
        // Google Sheets (issue #31): a 2-char insert at 1 must leave the caret at 3; Chrome
        // answered 2 — one edit behind — and the deferred AX read confirmed the replace
        // had landed. This is the case whose false demotion made a selected-but-not-editing
        // cell swallow everything typed until it was double-clicked.
        XCTAssertEqual(InPlaceProbe.verdict(axRegion: nil, caret: 2, start: 1, bs: 1,
                                            insertLength: 2, regionReadback: nil,
                                            inserted: "ươ"), .inconclusive)
        // AT or PAST the append position is real evidence of an append.
        XCTAssertEqual(InPlaceProbe.verdict(axRegion: nil, caret: 4, start: 2, bs: 1,
                                            insertLength: 1, regionReadback: nil,
                                            inserted: "ê"), .appended)   // append position
        XCTAssertEqual(InPlaceProbe.verdict(axRegion: nil, caret: 9, start: 2, bs: 1,
                                            insertLength: 1, regionReadback: nil,
                                            inserted: "ê"), .appended)   // far past it
        // Positive FAILURE evidence still wins over the impossible caret: if the target
        // region does not hold our text, the replace demonstrably didn't land.
        XCTAssertEqual(InPlaceProbe.verdict(axRegion: nil, caret: 0, start: 2, bs: 1,
                                            insertLength: 1, regionReadback: "e",
                                            inserted: "ê"), .appended)
        // …and so does the AX ground truth, in both directions.
        XCTAssertEqual(InPlaceProbe.verdict(axRegion: "ê", caret: 0, start: 2, bs: 1,
                                            insertLength: 1, regionReadback: nil,
                                            inserted: "ê"), .honored)
        XCTAssertEqual(InPlaceProbe.verdict(axRegion: "e", caret: 0, start: 2, bs: 1,
                                            insertLength: 1, regionReadback: nil,
                                            inserted: "ê"), .appended)
    }

    func testHonestCaretPlusStaleReadbackIsInconclusive() {
        // The two self-reports contradict each other: the caret says the replace landed
        // exactly where a compliant app puts it, the region read-back says our text is not
        // there. Chromium serves that read-back from a cache that is stale right after
        // insertText, and the deferred AX read confirmed the replace HAD landed in exactly
        // this state (Google Sheets #31, Jira before it) — so learn NOTHING here rather
        // than demote a healthy field. Before 2026-07-27 this returned .appended, which is
        // what silently pushed Sheets into marked text (where a not-yet-editing cell
        // swallows everything typed).
        XCTAssertEqual(InPlaceProbe.verdict(axRegion: nil, caret: 8, start: 7, bs: 1, insertLength: 1,
                                            regionReadback: "e", inserted: "ê"), .inconclusive)
        // Caret honored + region confirms → honored, as always.
        XCTAssertEqual(InPlaceProbe.verdict(axRegion: nil, caret: 8, start: 7, bs: 1, insertLength: 1,
                                            regionReadback: "ê", inserted: "ê"), .honored)
        // Region says our text is not there AND the caret does not describe a replace →
        // two independent signals agree it failed.
        XCTAssertEqual(InPlaceProbe.verdict(axRegion: nil, caret: 9, start: 7, bs: 1, insertLength: 1,
                                            regionReadback: "e", inserted: "ê"), .appended)
        // No caret, mismatching read-back: the only evidence we have, so trust it.
        XCTAssertEqual(InPlaceProbe.verdict(axRegion: nil, caret: nil, start: 7, bs: 1, insertLength: 1,
                                            regionReadback: "e", inserted: "ê"), .appended)
        // Lark's constant garbage caret is still caught, by HonorTracker (its own test):
        // mid-field it does not equal expectedReplace and is far behind it → appended.
        XCTAssertEqual(InPlaceProbe.verdict(axRegion: nil, caret: 1, start: 29, bs: 1, insertLength: 1,
                                            regionReadback: nil, inserted: "á"), .appended)
    }

    func testAXGroundTruthWins() {
        // The Accessibility read is authoritative over every self-reported signal.
        // Lark's case: caret says honored AND read-back is echoed to match, but AX
        // shows the old char → the replace never landed → marked text.
        XCTAssertEqual(InPlaceProbe.verdict(axRegion: "e", caret: 8, start: 7, bs: 1, insertLength: 1,
                                            regionReadback: "ê", inserted: "ê"), .appended)
        // AX confirms the text landed → in-place, regardless of a misreported caret.
        XCTAssertEqual(InPlaceProbe.verdict(axRegion: "ê", caret: 999, start: 7, bs: 1, insertLength: 1,
                                            regionReadback: nil, inserted: "ê"), .honored)
        // AX unavailable (nil) → fall back to caret/read-back logic.
        XCTAssertEqual(InPlaceProbe.verdict(axRegion: nil, caret: 8, start: 7, bs: 1, insertLength: 1,
                                            regionReadback: "ê", inserted: "ê"), .honored)
    }

    func testHonorTrackerRequiresTwoDistinctOffsets() {
        // A truthful caret confirms after two honored probes at different offsets.
        var t = InPlaceProbe.HonorTracker()
        XCTAssertFalse(t.recordHonored(expReplace: 5), "first honored never confirms")
        XCTAssertTrue(t.recordHonored(expReplace: 12), "second honored at a new offset confirms")
    }

    func testHonorTrackerRejectsConstantGarbageCaret() {
        // Lark's measured behavior: selectedRange().location == 1, always. It reads
        // "honored" only when expReplace coincides with 1 (start of an empty field) —
        // and can never produce a second honored at a DIFFERENT offset, so it is
        // never committed to in-place. Repeats at the same offset must not confirm.
        var t = InPlaceProbe.HonorTracker()
        XCTAssertFalse(t.recordHonored(expReplace: 1))
        XCTAssertFalse(t.recordHonored(expReplace: 1), "same offset repeat is no new information")
        XCTAssertFalse(t.recordHonored(expReplace: 1))
        // Mid-field the constant caret mismatches → verdict is appended (not honored),
        // so the tracker is never even consulted; the 2-strike fallback catches it.
        XCTAssertEqual(InPlaceProbe.verdict(axRegion: nil, caret: 1, start: 29, bs: 1, insertLength: 1,
                                            regionReadback: nil, inserted: "á"), .appended)
    }

    func testShouldProbeGating() {
        XCTAssertTrue(InPlaceProbe.shouldProbe(insertLength: 1, bs: 1, clear: 0, needsProbe: true))
        XCTAssertFalse(InPlaceProbe.shouldProbe(insertLength: 1, bs: 0, clear: 0, needsProbe: true),
                       "pure insert (bs==0) must never confirm — this was the false-positive")
        XCTAssertFalse(InPlaceProbe.shouldProbe(insertLength: 1, bs: 1, clear: 2, needsProbe: true),
                       "pending selection (clear>0) is not a clean replace")
        XCTAssertFalse(InPlaceProbe.shouldProbe(insertLength: 0, bs: 1, clear: 0, needsProbe: true),
                       "empty insert is not a probe")
        XCTAssertFalse(InPlaceProbe.shouldProbe(insertLength: 1, bs: 1, clear: 0, needsProbe: false),
                       "already classified — do not re-probe")
    }
}
