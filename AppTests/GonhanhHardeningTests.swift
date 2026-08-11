import XCTest
@testable import VietTelex

// App-side coverage for the gonhanh-learnings batch: remote-desktop passthrough
// routing (item 3) and tap-lifecycle safety without Accessibility (item 2).
final class GonhanhHardeningTests: XCTestCase {

    override func tearDown() {
        Accessibility.testTrustOverride = nil
        // A leaked poll timer would keep calling ensureRunning() every 3s on
        // RunLoop.main for the rest of the test run, across every other suite.
        TerminalTapController.shared._testDisarmTrustPoll()
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

    // Field report 2026-08-11: a process already running when the user granted
    // Accessibility never picked up the change — nothing re-attempts start() unless
    // an app/focus switch or the (occasionally missed) TCC notification fires. Fix:
    // ensureRunning() must itself arm a retry poll while untrusted, and disarm it the
    // moment trust returns, so a grant is noticed within one tick with no restart.
    func testEnsureRunningArmsRetryPollWhileUntrusted() {
        Accessibility.testTrustOverride = false
        let controller = TerminalTapController.shared
        controller.ensureRunning()
        XCTAssertTrue(controller._testTrustPollIsRunning,
                      "still untrusted after ensureRunning() — the retry poll must be armed")
    }

    func testTrustPollDisarmsExplicitly() {
        Accessibility.testTrustOverride = false
        let controller = TerminalTapController.shared
        controller.ensureRunning()
        XCTAssertTrue(controller._testTrustPollIsRunning)
        controller._testDisarmTrustPoll()
        XCTAssertFalse(controller._testTrustPollIsRunning)
    }

    /// Repeated calls while still untrusted (activateServer fires on every app
    /// switch) must reuse the SAME poll timer, not leak a fresh one each time —
    /// a leaked timer would fire ensureRunning() at an ever-increasing rate.
    func testEnsureRunningDoesNotLeakDuplicatePollTimers() {
        Accessibility.testTrustOverride = false
        let controller = TerminalTapController.shared
        controller.ensureRunning()
        let firstToken = controller._testTrustPollToken
        XCTAssertNotNil(firstToken)
        controller.ensureRunning()
        controller.ensureRunning()
        XCTAssertEqual(controller._testTrustPollToken, firstToken,
                       "second/third ensureRunning() while untrusted must not replace the poll timer")
    }

    /// A fresh arm after an explicit disarm must actually re-arm (proves the dedup
    /// guard keys off "is one running right now", not off "has one ever run" — a
    /// latched flag would leave the poll permanently disabled after any disarm).
    func testTrustPollCanReArmAfterDisarm() {
        Accessibility.testTrustOverride = false
        let controller = TerminalTapController.shared
        controller.ensureRunning()
        XCTAssertNotNil(controller._testTrustPollToken)
        controller._testDisarmTrustPoll()
        XCTAssertNil(controller._testTrustPollToken)

        controller.ensureRunning()
        XCTAssertNotNil(controller._testTrustPollToken, "must re-arm, not stay disarmed forever")
    }
}
