import XCTest
@testable import VietTelex

// App-side coverage for the gonhanh-learnings batch: remote-desktop passthrough
// routing (item 3) and tap-lifecycle safety without Accessibility (item 2).
final class GonhanhHardeningTests: XCTestCase {

    override func tearDown() {
        Accessibility.testTrustOverride = nil
        super.tearDown()
    }

    func testRemoteDesktopPassthroughRouting() {
        for id in ["com.carriez.rustdesk", "com.philandro.anydesk"] {
            XCTAssertEqual(AppState.shared.autoResolvedMode(id), .passthrough, id)
            XCTAssertTrue(AppState.builtInPassthroughApps.contains(id), "\(id) missing from plist")
        }
    }

    /// iPhone Mirroring reuses the OLD Screen Sharing bundle id — it used to sit in
    /// the remote-desktop passthrough bucket above, until maintainer field-test
    /// 07/08/2026 confirmed it bridges Continuity to a REAL text field on the phone
    /// (not raw scancodes for a guest OS), so it belongs in inPlace instead.
    func testIPhoneMirroringIsInPlaceNotPassthrough() {
        XCTAssertEqual(AppState.shared.autoResolvedMode("com.apple.ScreenContinuity"), .inPlace)
        XCTAssertFalse(AppState.builtInPassthroughApps.contains("com.apple.ScreenContinuity"))
    }

    func testBundledPlistCarriesTheNewRules() {
        // the SHIPPED resource (not just the repo file) must contain the ids
        guard let url = Bundle(for: TelexInputController.self)
                .url(forResource: "typing-modes", withExtension: "yml"),
              let data = try? Data(contentsOf: url),
              let dict = ShortcutImporter.parse(data)
        else { return XCTFail("bundled typing-modes.yml unreadable") }
        XCTAssertEqual(dict["com.carriez.rustdesk"], "passthrough")
        XCTAssertEqual(dict["com.philandro.anydesk"], "passthrough")
        XCTAssertEqual(dict["com.apple.ScreenContinuity"], "inPlace")
    }

    // Watchdog/lifecycle safety: with Accessibility revoked, ensureRunning must
    // be a no-op that never creates a tap (the watchdog calls it every 3s now —
    // it has to be safe to call from any state).
    func testEnsureRunningIsSafeWithoutTrust() {
        Accessibility.testTrustOverride = false
        let controller = TerminalTapController.shared
        controller.ensureRunning()
        controller.ensureRunning()          // idempotent
        XCTAssertFalse(controller.isRunning)
    }
}
