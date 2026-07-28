import XCTest
@testable import VietTelex

// The Settings window lives in the INPUT METHOD's process, on the same main thread that
// serves keystrokes — so its work is typing latency. Tester report 2026-07-28: "mở settings
// lên lâu là bị đơ đơ, tắt đi thì trở lại bình thường". Cause: the mode table rebuilt on
// EVERY NSWindow.didBecomeKey (which fires for every window in the process, and the user's
// flow is alt-tabbing between Settings and the app under test), and each rebuild ran ~50
// LaunchServices lookups. These tests pin both guards.
final class SettingsReloadCostTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // The table's labels ask about Accessibility; pin it so the rows are deterministic.
        Accessibility.testTrustOverride = true
    }

    override func tearDown() {
        Accessibility.testTrustOverride = nil
        super.tearDown()
    }

    /// "Installed?" is a LaunchServices round trip per bundle id; apps do not come and go
    /// while a window is open, so each id must be looked up at most once per session.
    func testInstalledLookupsAreMemoized() {
        SettingsModel.installedCache.removeAll()
        let model = SettingsModel(selected: .modeTable)
        model.reloadModeTable()
        let afterFirst = SettingsModel.installedCache.count
        XCTAssertGreaterThan(afterFirst, 0, "the reload must populate the cache")

        model.reloadModeTable()
        XCTAssertEqual(SettingsModel.installedCache.count, afterFirst,
                       "a second reload must not add lookups — every id was already known")
    }

    /// Throttled reload: at most one rebuild per second, no matter how many windows become
    /// key. Observed through `modeRows`: a skipped reload leaves the emptied rows empty.
    func testThrottledReloadSkipsWithinTheWindow() {
        let model = SettingsModel(selected: .modeTable)
        model.reloadModeTable()
        XCTAssertFalse(model.modeRows.isEmpty, "a direct reload always rebuilds")

        model.modeRows = []                       // make a rebuild observable
        model.reloadModeTableThrottled()          // immediately after → must be skipped
        XCTAssertTrue(model.modeRows.isEmpty, "a second reload inside the window must be skipped")
    }

    func testThrottledReloadRunsOnceTheWindowHasPassed() {
        let model = SettingsModel(selected: .modeTable)
        model.reloadModeTable()
        model.modeRows = []
        model.lastModeReloadAt -= 2               // pretend the last rebuild was 2s ago
        model.reloadModeTableThrottled()
        XCTAssertFalse(model.modeRows.isEmpty, "outside the window the rebuild must happen")
    }

    /// A direct (unthrottled) reload must also RESET the throttle clock, or the next
    /// window-focus reload would fire immediately after it and undo the guard.
    func testDirectReloadStampsTheThrottleClock() {
        let model = SettingsModel(selected: .modeTable)
        model.lastModeReloadAt = 0
        model.reloadModeTable()
        XCTAssertGreaterThan(model.lastModeReloadAt, 0, "reloadModeTable must stamp the clock")
    }
}
