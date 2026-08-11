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
        XCTAssertEqual(AppState.gateRouting(all, trusted: { true },
                                            wantsSelection: { XCTFail("sel .yes must not consult the detector"); return false },
                                            wantsMarkedField: { XCTFail("sel .yes must not consult the marked verdict"); return false }),
                       R(tap: true, selection: true, emptyReset: true))
        XCTAssertEqual(AppState.gateRouting(all, trusted: { false }, wantsSelection: { false },
                                            wantsMarkedField: { false }), R())
    }

    func testGatePerFieldConsultsTheDetectorExactlyOnce() {
        var reads = 0
        let w = W(tap: false, sel: .perField, empty: false)
        let r = AppState.gateRouting(w, trusted: { true }, wantsSelection: { reads += 1; return true },
                                     wantsMarkedField: { XCTFail("omnibox must not consult the marked verdict"); return false })
        XCTAssertEqual(r, R(tap: false, selection: true, emptyReset: false))
        XCTAssertEqual(reads, 1)
        XCTAssertFalse(AppState.gateRouting(w, trusted: { true }, wantsSelection: { false },
                                            wantsMarkedField: { false }).selection)
    }

    /// The laziness contract: no wants → NEITHER external is touched (a plain
    /// in-place app's keystroke pays zero TCC/detector cost), and untrusted →
    /// the detector is never touched.
    func testGateIsLazyOnBothExternals() {
        _ = AppState.gateRouting(W(),
                                 trusted: { XCTFail("no wants → trusted must not be read"); return true },
                                 wantsSelection: { XCTFail("no wants → detector must not be read"); return false },
                                 wantsMarkedField: { XCTFail("no wants → marked verdict must not be read"); return false })
        _ = AppState.gateRouting(W(tap: true, sel: .perField, empty: false),
                                 trusted: { false },
                                 wantsSelection: { XCTFail("untrusted → detector must not be read"); return false },
                                 wantsMarkedField: { XCTFail("untrusted → marked verdict must not be read"); return false })
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

    // POLICY 2026-08-06 (maintainer): browser PAGE CONTENT routes to the TAP
    // backspace-retype path by default — the only channel every web editor must
    // handle (the EVKey/OpenKey model). insertText(replacementRange:) has no
    // contract with JS editors: Docs appended + killed ⌫ (07-30), Discord appended
    // while EVERY self-report said honored (08-05, provably undetectable), Zalo
    // froze with a constant caret (08-06) — three per-host patches in one week.
    // The host allowlist is GONE; this truth table IS the policy now.
    func testPageContentRoutesToTap() {
        let w = W(tap: false, sel: .perField, empty: false)
        let r = AppState.gateRouting(w, trusted: { true },
                                     wantsSelection: { false },      // page content, not omnibox
                                     wantsMarkedField: { false })    // not the Docs class
        XCTAssertEqual(r, R(tap: true, selection: false, emptyReset: false))
    }

    func testMarkedClassFieldFallsThroughToIMKit() {
        // Google-Docs-class field: neither tap nor selection — IMKit's usesMarkedNow
        // picks it up via wantsMarkedField and composes with marked text.
        let w = W(tap: false, sel: .perField, empty: false)
        let r = AppState.gateRouting(w, trusted: { true },
                                     wantsSelection: { false },
                                     wantsMarkedField: { true })
        XCTAssertEqual(r, R(tap: false, selection: false, emptyReset: false))
    }

    func testOmniboxStillRoutesToSelection() {
        let w = W(tap: false, sel: .perField, empty: false)
        let r = AppState.gateRouting(w, trusted: { true },
                                     wantsSelection: { true },
                                     wantsMarkedField: { XCTFail("omnibox settled before the marked verdict"); return false })
        XCTAssertEqual(r, R(tap: false, selection: true, emptyReset: false))
    }
}

// Spotlight overlay vs tap-family routing: FrontmostApp stays the app BEHIND the
// overlay (iTerm/Chrome), so the tap's routing verdict says "compose" while the keys
// actually land in Spotlight's field — whose inline autocomplete eats a synthetic
// Backspace as "delete the selected suggestion", reordering the word (field report
// 2026-07-31: "pas" over iTerm → garbled; log: tap-emit mode=backspace while
// client=com.apple.Spotlight). Contract: raw passthrough unless Spotlight itself is
// explicitly pinned to a tap-family mode.
final class SpotlightOverlayGateTests: XCTestCase {
    func testOverlayForcesRawForUnpinnedSpotlight() {
        for pin: AppState.AppMode? in [nil, .auto, .inPlace, .marked, .axDetect, .passthrough] {
            XCTAssertTrue(TerminalTapController.spotlightOverlayForcesRaw(visible: true, manualPin: pin),
                          "pin=\(String(describing: pin))")
        }
    }
    func testExplicitTapFamilyPinKeepsComposing() {
        for pin: AppState.AppMode in [.tap, .selection, .emptyReset] {
            XCTAssertFalse(TerminalTapController.spotlightOverlayForcesRaw(visible: true, manualPin: pin))
        }
    }
    func testNoOverlayNeverForcesRaw() {
        XCTAssertFalse(TerminalTapController.spotlightOverlayForcesRaw(visible: false, manualPin: nil))
        XCTAssertFalse(TerminalTapController.spotlightOverlayForcesRaw(visible: false, manualPin: .tap))
    }
}

// Issue #32 (field report 2026-08-11): Spotlight opened over a tap/per-field app
// (Chrome, a terminal) composed NOTHING — raw "dduowcj" stayed on screen. Live trace
// showed the client id resolved correctly (client=com.apple.Spotlight) but tapRouting
// still returned tapDefer=true, because it merges in the FRONTMOST app's wants
// (Chrome: sel=.perField) even though Spotlight's own id is never uncertain. Same word
// over TextMate (in-place, no tap wants) worked — the merge contributed nothing there.
final class SpotlightClientIDNeverMergesWithFrontTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Accessibility.testTrustOverride = true   // gateRouting is a no-op untrusted
    }

    override func tearDown() {
        Accessibility.testTrustOverride = nil
        super.tearDown()
    }

    func testSpotlightOverChromeStillComposesInPlace() {
        let r = AppState.shared.tapRouting(AppState.spotlightBundleID, front: "com.google.Chrome")
        XCTAssertFalse(r.tapDefer, "Spotlight's own id must decide routing, not the app behind the overlay")
    }

    func testSpotlightOverTerminalStillComposesInPlace() {
        let r = AppState.shared.tapRouting(AppState.spotlightBundleID, front: "com.apple.Terminal")
        XCTAssertFalse(r.tapDefer)
    }

    func testNonSpotlightClientsStillMergeWithFront() {
        // The nil/uncertain-id safety net must survive for everyone else.
        let r = AppState.shared.tapRouting(nil, front: "com.apple.Terminal")
        XCTAssertTrue(r.tapDefer, "nil client id must still fall back to the frontmost app's rule")
    }
}

// Field report 2026-08-11: Esc in Spotlight resets the query without closing the
// overlay, cycling activateServer(iTerm)→activateServer(Spotlight) within ~1ms. The
// freshly re-activated session's client.selectedRange() then reported a stale huge
// caret (start=6632 in a field that was actually empty), garbling the next word
// ("được" → "dđuưoựoược"). TelexInputController.spotlightReactivatedTooSoon pins the
// distrust window so the anchor at that first key falls back to the safe
// no-tracking path instead of trusting the bogus caret.
final class SpotlightRapidReactivationTests: XCTestCase {
    private let oneSecondNs: UInt64 = 1_000_000_000

    func testFirstEverActivationIsNeverDistrusted() {
        XCTAssertFalse(TelexInputController.spotlightReactivatedTooSoon(now: oneSecondNs, lastActivateNs: 0))
    }

    func testReactivationWithinWindowIsDistrusted() {
        let last: UInt64 = 10 * oneSecondNs
        let now = last + 3 * oneSecondNs   // matches the field report's ~3.27s gap
        XCTAssertTrue(TelexInputController.spotlightReactivatedTooSoon(now: now, lastActivateNs: last))
    }

    func testReactivationAfterWindowIsTrusted() {
        let last: UInt64 = 10 * oneSecondNs
        let now = last + 6 * oneSecondNs
        XCTAssertFalse(TelexInputController.spotlightReactivatedTooSoon(now: now, lastActivateNs: last))
    }

    func testExactlyAtWindowBoundaryIsTrusted() {
        let last: UInt64 = 10 * oneSecondNs
        let now = last + 5 * oneSecondNs
        XCTAssertFalse(TelexInputController.spotlightReactivatedTooSoon(now: now, lastActivateNs: last))
    }
}

// noteFocused: activateServer(com.apple.Spotlight) là bằng chứng chắc chắn overlay
// đang mở — cache phải TRUE ngay lập tức, không đợi CGWindowList scan (burst "pas"
// 2026-07-31: phím dấu emit vào overlay khi cache còn false).
final class SpotlightNoteFocusedTests: XCTestCase {
    func testNoteFocusedStampsVisibleImmediately() {
        SpotlightDetector._testSetVisible(false)
        XCTAssertFalse(SpotlightDetector._testVisible)
        SpotlightDetector.noteFocused()
        XCTAssertTrue(SpotlightDetector._testVisible)
        SpotlightDetector._testSetVisible(false)   // trả trạng thái cho test khác
    }

    // Field report 2026-08-11: typing "được" in Chrome's omnibox right away after
    // closing Spotlight produced "dduwợc" — the first four keys landed raw because
    // isVisible kept reporting stale-true (DetectorBackoff's TTL had grown during
    // Spotlight's long-open, stable session) for 500ms+ after activateServer had
    // already moved to Chrome. noteUnfocused() must clear the cache immediately,
    // the same way noteFocused() sets it — activateServer(anyOtherClient) is
    // equally authoritative proof in the opposite direction.
    func testNoteUnfocusedClearsVisibleImmediately() {
        SpotlightDetector._testSetVisible(true)
        XCTAssertTrue(SpotlightDetector._testVisible)
        SpotlightDetector.noteUnfocused()
        XCTAssertFalse(SpotlightDetector._testVisible)
    }

    /// End-to-end: chains noteUnfocused() into the ACTUAL gate the tap consults per
    /// keystroke (spotlightOverlayForcesRaw), pinning the fix at its point of use —
    /// not just at the cache getter. Before the fix, a long-open Spotlight session
    /// left `visible` stale-true here for 500ms+ after activateServer had already
    /// moved to Chrome, so the gate kept forcing raw passthrough into the omnibox.
    func testNoteUnfocusedStopsOverlayFromForcingRawOnTheNextKey() {
        SpotlightDetector._testSetVisible(true)   // Spotlight was just open
        XCTAssertTrue(TerminalTapController.spotlightOverlayForcesRaw(
            visible: SpotlightDetector._testVisible, manualPin: nil),
            "sanity: while still marked visible, the gate must force raw")

        SpotlightDetector.noteUnfocused()          // activateServer moved to Chrome
        XCTAssertFalse(TerminalTapController.spotlightOverlayForcesRaw(
            visible: SpotlightDetector._testVisible, manualPin: nil),
            "the very next key must be allowed to compose, not forced raw")
    }
}

// POLICY 2026-08-06, nửa còn lại: browser (axDetect) KHÔNG có quyền Trợ năng thì
// degrade sang MARKED TEXT (kênh composition — hợp đồng chuẩn web mà mọi editor
// phải hỗ trợ vì người dùng CJK), không còn rơi về in-place như cũ. In-place chính
// là kênh không-hợp-đồng đã gây toàn bộ loạt bug web-editor đầu tháng 8. Quy tắc
// này khớp với nguyên tắc đã có sẵn cho mọi mode tap-family: "thiếu AX → marked,
// không bao giờ âm thầm về in-place".
final class UntrustedBrowserFallbackTests: XCTestCase {
    override func tearDown() {
        Accessibility.testTrustOverride = nil
        super.tearDown()
    }

    func testUntrustedBuiltInBrowserDegradesToMarked() {
        Accessibility.testTrustOverride = false
        XCTAssertTrue(AppState.shared.usesMarkedText("com.google.Chrome"),
                      "browser without AX must compose with marked text")
        XCTAssertTrue(AppState.shared.usesMarkedText("com.apple.Safari"))
    }

    func testTrustedBrowserDoesNotForceMarked() {
        Accessibility.testTrustOverride = true
        XCTAssertFalse(AppState.shared.usesMarkedText("com.google.Chrome"),
                       "with AX the per-field routing decides, not blanket marked")
    }

    func testUntrustedNonBrowserRulesUnchanged() {
        Accessibility.testTrustOverride = false
        // Learned/built-in fallback apps already degraded to marked before this policy.
        XCTAssertTrue(AppState.shared.usesMarkedText("com.hnc.Discord"))
        // Built-in in-place apps stay in-place even untrusted (probed-good contract).
        XCTAssertFalse(AppState.shared.usesMarkedText("com.apple.Notes"))
    }
}

// POLICY 06/08/2026 "app lạ đi kênh an toàn": app không có rule ở đâu cả (không
// manual, không built-in, không learned fallback) → TAP khi có Accessibility,
// MARKED khi không — thay cho in-place + probe-học. Lý do: Discord (05/08) và
// Lark (06/08, bundle id trôi khỏi rule) chứng minh lỗi in-place có thể VÔ HÌNH
// với self-report — probe "học in-place OK" trong khi màn hình sai. Tap và
// marked là 2 kênh duy nhất có hợp đồng. Toggle Thử Nghiệm quay về hành vi cũ.
final class UnknownAppPolicyTests: XCTestCase {

    private let unknown = "com.example.some-random-app"
    private var savedPolicy = true

    override func setUp() {
        super.setUp()
        savedPolicy = AppState.shared.safeUnknownApps
    }

    override func tearDown() {
        AppState.shared.safeUnknownApps = savedPolicy
        AppState.shared.unmarkInPlaceGood(unknown)
        super.tearDown()
    }

    func testUnknownAppIsTapFamilyByDefault() {
        AppState.shared.safeUnknownApps = true
        XCTAssertEqual(AppState.shared.autoResolvedMode(unknown), .tap,
                       "app lạ phải hiện tap trong menu, không phải 'chưa dò'")
        XCTAssertTrue(AppState.shared.usesMarkedText(unknown),
                      "marked là degradation của tap-family khi thiếu Accessibility")
        XCTAssertFalse(AppState.shared.needsProbe(unknown),
                       "không còn gì để dò — one-shot probe nghỉ hưu dưới policy này")
    }

    func testCuratedInPlaceListIsUntouched() {
        AppState.shared.safeUnknownApps = true
        XCTAssertEqual(AppState.shared.autoResolvedMode("com.apple.Notes"), .inPlace)
        XCTAssertFalse(AppState.shared.usesMarkedText("com.apple.Notes"))
        // TextEdit vào list built-in batch 06/08 (maintainer field-verified).
        XCTAssertEqual(AppState.shared.autoResolvedMode("com.apple.TextEdit"), .inPlace)
    }

    /// probedAppsCache là chính cái cache self-report mà policy này không tin —
    /// Lark học nhầm "in-place OK" từ caret thật thà trong khi editor nuốt edit.
    /// Máy đã học nhầm phải TỰ KHỎI khi update, không cần xoá learned data.
    func testLearnedInPlaceNoLongerGrantsInPlace() {
        AppState.shared.markInPlaceGood(unknown)
        AppState.shared.safeUnknownApps = true
        XCTAssertEqual(AppState.shared.autoResolvedMode(unknown), .tap,
                       "learned in-place không được cứu app lạ khỏi kênh an toàn")
        XCTAssertTrue(AppState.shared.usesMarkedText(unknown))
    }

    func testLegacyToggleRestoresProbeAndLearn() {
        AppState.shared.safeUnknownApps = false
        XCTAssertNil(AppState.shared.autoResolvedMode(unknown), "legacy: chưa dò → nil")
        AppState.shared.markInPlaceGood(unknown)
        XCTAssertEqual(AppState.shared.autoResolvedMode(unknown), .inPlace,
                       "legacy: learned in-place lại có hiệu lực")
        XCTAssertFalse(AppState.shared.usesMarkedText(unknown))
    }
}
