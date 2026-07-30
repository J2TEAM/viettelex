import XCTest
@testable import VietTelex

// The per-key routing used to be 6-8 separate AppState calls (each its own lock trip,
// several re-reading Accessibility.isTrusted). tapRouting() collapses that into ONE
// lock + one trusted read + at most one detector read. These tests pin the pure parts:
// the OR-merge across the two consulted ids, the gate order, and — critically — the
// LAZINESS contract: a key in a plain in-place app must not pay for a TCC read or an
// AX field scan, exactly as the legacy per-mode getters behaved.
final class RoutingDecisionTests: XCTestCase {

    private typealias W = AppState.TapWants
    private typealias R = AppState.TapRouting

    // MARK: merge

    func testMergeORsEachFamily() {
        let tap = W(tap: true, sel: .no, empty: false)
        let empty = W(tap: false, sel: .no, empty: true)
        XCTAssertEqual(AppState.mergedWants(tap, empty), W(tap: true, sel: .no, empty: true))
        XCTAssertEqual(AppState.mergedWants(W(), W()), W())
    }

    func testMergeSelYesOutranksPerField() {
        // Manual .selection pin means selection UNCONDITIONALLY — merging with a
        // per-field browser verdict must not demote it back to detector-dependent.
        let yes = W(tap: false, sel: .yes, empty: false)
        let perField = W(tap: false, sel: .perField, empty: false)
        XCTAssertEqual(AppState.mergedWants(yes, perField).sel, .yes)
        XCTAssertEqual(AppState.mergedWants(perField, yes).sel, .yes)
        XCTAssertEqual(AppState.mergedWants(perField, W()).sel, .perField)
    }

    // MARK: gate

    func testGateAppliesTrustToEveryFamily() {
        let all = W(tap: true, sel: .yes, empty: true)
        XCTAssertEqual(AppState.gateRouting(all, trusted: { true }, wantsSelection: { XCTFail("sel .yes must not consult the detector"); return false }),
                       R(tap: true, selection: true, emptyReset: true))
        XCTAssertEqual(AppState.gateRouting(all, trusted: { false }, wantsSelection: { false }), R())
    }

    func testGatePerFieldConsultsTheDetectorExactlyOnce() {
        var reads = 0
        let w = W(tap: false, sel: .perField, empty: false)
        let r = AppState.gateRouting(w, trusted: { true }, wantsSelection: { reads += 1; return true })
        XCTAssertEqual(r, R(tap: false, selection: true, emptyReset: false))
        XCTAssertEqual(reads, 1)
        XCTAssertFalse(AppState.gateRouting(w, trusted: { true }, wantsSelection: { false }).selection)
    }

    /// The laziness contract: no wants → NEITHER external is touched (a plain
    /// in-place app's keystroke pays zero TCC/detector cost), and untrusted →
    /// the detector is never touched.
    func testGateIsLazyOnBothExternals() {
        _ = AppState.gateRouting(W(),
                                 trusted: { XCTFail("no wants → trusted must not be read"); return true },
                                 wantsSelection: { XCTFail("no wants → detector must not be read"); return false })
        _ = AppState.gateRouting(W(tap: true, sel: .perField, empty: false),
                                 trusted: { false },
                                 wantsSelection: { XCTFail("untrusted → detector must not be read"); return false })
    }

    // MARK: equivalence with the legacy per-mode getters (shared _rawWants core)

    /// tapRouting and the legacy getters resolve the same wants from the same core;
    /// with the built-in rule table this pins tap/perField/empty membership end to end.
    /// (Gates depend on live AX state, so equivalence is asserted at tapDefer level —
    /// under the test host both sides see the same isTrusted/detector answers.)
    func testSnapshotAgreesWithLegacyGettersForBuiltInRules() {
        let s = AppState.shared
        let ids: [String?] = ["com.apple.Terminal",        // built-in tap
                              "com.apple.Safari",          // built-in axDetect (perField)
                              "com.microsoft.Excel",       // built-in emptyReset (if ruled)
                              "com.apple.Notes",           // built-in inPlace
                              "definitely.not.installed",  // unknown
                              nil]
        for id in ids {
            for front in ids {
                let r = s.tapRouting(id, front: front)
                let legacy = s.usesTapMode(id) || s.usesTapMode(front)
                    || s.usesSelectionReplace(id) || s.usesSelectionReplace(front)
                    || s.usesEmptyReset(id) || s.usesEmptyReset(front)
                XCTAssertEqual(r.tapDefer, legacy, "id=\(id ?? "nil") front=\(front ?? "nil")")
            }
        }
    }
}
