import XCTest
@testable import VietTelex

// Support-layer coverage: DebugLog ring semantics, Updater version logic +
// stubbed network paths, the Accessibility trust cache, and the safe (non-posting)
// SyntheticKeyboard state helpers. Detector getters are smoke-read only — their
// values depend on live system state (windows, AX), so asserting them would flake.
final class AppSupportTests: XCTestCase {

    override func tearDown() {
        Accessibility.testTrustOverride = nil
        AppState.shared.debugLogging = false
        super.tearDown()
    }

    // MARK: DebugLog

    func testDebugLogRing() {
        let wasOn = AppState.shared.debugLogging
        defer { AppState.shared.debugLogging = wasOn }
        AppState.shared.debugLogging = false
        DebugLog.clear()
        DebugLog.log("must NOT be recorded")
        XCTAssertFalse(DebugLog.snapshot(header: []).contains("must NOT be recorded"))
        AppState.shared.debugLogging = true
        DebugLog.log("recorded line")
        let snap = DebugLog.snapshot(header: ["HEADER"])
        XCTAssertTrue(snap.contains("HEADER"))
        XCTAssertTrue(snap.contains("recorded line"))
        // Ring caps at 400: the oldest line is evicted, never a crash.
        for i in 0..<450 { DebugLog.log("filler \(i)") }
        let full = DebugLog.snapshot(header: [])
        XCTAssertFalse(full.contains("recorded line"))
        XCTAssertTrue(full.contains("filler 449"))
        DebugLog.clear()
        XCTAssertTrue(DebugLog.snapshot(header: []).contains("log empty"))
    }

    // MARK: Updater — pure logic

    func testVersionCompare() {
        XCTAssertTrue(UpdateCheck.isNewer("1.3.1", than: "1.3.0"))
        XCTAssertTrue(UpdateCheck.isNewer("1.10.0", than: "1.9.9"))   // numeric, not lexical
        XCTAssertTrue(UpdateCheck.isNewer("1.3.0.1", than: "1.3.0"))  // length mismatch
        XCTAssertFalse(UpdateCheck.isNewer("1.3.0", than: "1.3.0"))
        XCTAssertFalse(UpdateCheck.isNewer("1.2.9", than: "1.3.0"))
        XCTAssertFalse(UpdateCheck.isNewer("garbage", than: "1.0"))   // non-numeric → 0
        XCTAssertFalse(UpdateCheck.currentVersion().isEmpty)
    }

    // MARK: Updater — network paths via a URLProtocol stub

    func testCheckPathsAgainstStubbedNetwork() async {
        URLProtocol.registerClass(StubURLProtocol.self)
        defer { URLProtocol.unregisterClass(StubURLProtocol.self) }

        // Stable manifest newer than current → .update with the manifest URL.
        StubURLProtocol.responder = { url in
            if url.absoluteString.contains("stable.json") {
                return (200, #"{"version":"99.0.0","url":"https://example.com/rel"}"#)
            }
            return (200, #"{"tag_name":"v99.0.0","html_url":"https://example.com/gh"}"#)
        }
        if case let .update(latest, url) = await UpdateCheck.checkStable() {
            XCTAssertEqual(latest, "99.0.0")
            XCTAssertEqual(url.absoluteString, "https://example.com/rel")
        } else { XCTFail("expected .update from stable") }
        if case let .update(latest, _) = await UpdateCheck.check() {
            XCTAssertEqual(latest, "99.0.0")
        } else { XCTFail("expected .update from latest") }

        // Same version → upToDate.
        let cur = UpdateCheck.currentVersion()
        StubURLProtocol.responder = { url in
            url.absoluteString.contains("stable.json")
                ? (200, #"{"version":"\#(cur)"}"#)
                : (200, #"{"tag_name":"v\#(cur)"}"#)
        }
        if case .upToDate = await UpdateCheck.checkStable() {} else { XCTFail("stable upToDate") }
        if case .upToDate = await UpdateCheck.check() {} else { XCTFail("latest upToDate") }

        // HTTP error and junk payload → .failed, never a crash.
        StubURLProtocol.responder = { _ in (500, "boom") }
        if case .failed = await UpdateCheck.checkStable() {} else { XCTFail("stable failed") }
        if case .failed = await UpdateCheck.check() {} else { XCTFail("latest failed") }
        StubURLProtocol.responder = { _ in (200, "not json at all") }
        if case .failed = await UpdateCheck.checkStable() {} else { XCTFail("stable junk") }
        if case .failed = await UpdateCheck.check() {} else { XCTFail("latest junk") }
    }

    func testMaybeAutoCheckGuards() {
        let s = AppState.shared
        let savedOptIn = s.autoUpdateCheck
        let savedAt = s.lastAutoUpdateCheckAt
        defer { s.autoUpdateCheck = savedOptIn; s.lastAutoUpdateCheckAt = savedAt }
        // Opt-out: returns without touching the throttle timestamp.
        s.autoUpdateCheck = false
        s.lastAutoUpdateCheckAt = 0
        UpdateCheck.maybeAutoCheck()
        XCTAssertEqual(s.lastAutoUpdateCheckAt, 0)
        // Opted in but checked recently: throttle holds.
        s.autoUpdateCheck = true
        let now = Date().timeIntervalSince1970
        s.lastAutoUpdateCheckAt = now
        UpdateCheck.maybeAutoCheck()
        XCTAssertEqual(s.lastAutoUpdateCheckAt, now)
    }

    // MARK: Updater — bundle install (the "permission stuck after update" fix)

    // installBundle must swap in the new bundle WHOLESALE. The old `ditto newApp dest`
    // merged — it overwrote same-named files but left orphans from resources a new
    // version dropped/renamed, breaking the code seal so tccd refused the event tap.
    // These build throwaway directory trees (not real .app bundles) and assert the
    // on-disk result is byte-identical to the source, with no merge residue.
    private func writeTree(_ files: [String: String], at root: URL) throws {
        for (rel, body) in files {
            let f = root.appendingPathComponent(rel)
            try FileManager.default.createDirectory(at: f.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try body.write(to: f, atomically: true, encoding: .utf8)
        }
    }

    private func readTree(at root: URL) -> [String: String] {
        var out: [String: String] = [:]
        let base = root.standardizedFileURL.path
        guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        else { return out }
        for case let url as URL in en {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            guard !isDir.boolValue else { continue }
            let rel = String(url.standardizedFileURL.path.dropFirst(base.count + 1))
            out[rel] = (try? String(contentsOf: url, encoding: .utf8)) ?? "<binary>"
        }
        return out
    }

    func testInstallBundleFreshInstall() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("vt-install-fresh-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let src = tmp.appendingPathComponent("staging/VietTelex.app")
        let dest = tmp.appendingPathComponent("Input Methods/VietTelex.app")
        let payload = ["Contents/MacOS/VietTelex": "v2-binary",
                       "Contents/Info.plist": "v2-plist"]
        try writeTree(payload, at: src)

        try SelfUpdater.installBundle(from: src, to: dest)   // no existing dest → move

        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))
        XCTAssertEqual(readTree(at: dest), payload)
        XCTAssertFalse(FileManager.default.fileExists(atPath: src.path), "source should be consumed")
    }

    func testInstallBundleReplacesWholesaleAndDropsOrphans() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("vt-install-replace-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let src = tmp.appendingPathComponent("staging/VietTelex.app")
        let dest = tmp.appendingPathComponent("Input Methods/VietTelex.app")

        // Old installed bundle: has a resource the new version renames away.
        try writeTree(["Contents/MacOS/VietTelex": "v1-binary",
                       "Contents/Info.plist": "v1-plist",
                       "Contents/Resources/old-lexicon.dat": "STALE",       // orphan-to-be
                       "Contents/CodeResources": "v1-seal"], at: dest)
        // New bundle: binary changed, lexicon renamed, no old-lexicon.dat.
        let payload = ["Contents/MacOS/VietTelex": "v2-binary",
                       "Contents/Info.plist": "v2-plist",
                       "Contents/Resources/lexicon-v2.dat": "FRESH",
                       "Contents/CodeResources": "v2-seal"]
        try writeTree(payload, at: src)

        try SelfUpdater.installBundle(from: src, to: dest)

        // Wholesale: dest is byte-identical to the new artifact — the orphan is GONE
        // (a merge would have kept old-lexicon.dat and broken the seal).
        XCTAssertEqual(readTree(at: dest), payload)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: dest.appendingPathComponent("Contents/Resources/old-lexicon.dat").path),
            "orphaned file from the old version must be removed (no merge)")
        // No leftover backup dir beside the installed bundle.
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: dest.deletingLastPathComponent().appendingPathComponent("VietTelex.app.bak").path),
            "backup must not linger after a successful replace")
        XCTAssertFalse(FileManager.default.fileExists(atPath: src.path), "source should be consumed")
    }

    // MARK: Accessibility trust cache

    func testTrustOverrideAndCache() {
        Accessibility.testTrustOverride = true
        XCTAssertTrue(Accessibility.isTrusted)
        Accessibility.testTrustOverride = false
        XCTAssertFalse(Accessibility.isTrusted)
        Accessibility.testTrustOverride = nil
        Accessibility.invalidateCache()
        let real = Accessibility.isTrusted     // whatever TCC says on this machine…
        XCTAssertEqual(Accessibility.isTrusted, real)   // …the cache answers the same
    }

    // MARK: SyntheticKeyboard state helpers (safe: nothing is posted)

    func testSyntheticKeyboardStateHelpers() {
        SyntheticKeyboard.resetBreaker()
        XCTAssertFalse(SyntheticKeyboard.tripped)
        XCTAssertTrue(SyntheticKeyboard.queueDrained())
        SyntheticKeyboard.noteObservedSynthetic()   // underflow-safe at zero
        XCTAssertTrue(SyntheticKeyboard.queueDrained())
    }

    // MARK: Detector getters — smoke reads (values are live system state)

    func testDetectorSmokeReads() {
        _ = SpotlightDetector.isVisible
        _ = FocusedFieldDetector.wantsSelection
        _ = FocusedFieldDetector.isTextInput
    }
}

/// Minimal URLProtocol stub: answers every request from `responder` without
/// touching the network. Registered per-test; URLSession.shared consults
/// registered protocol classes for its default configuration.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responder: ((URL) -> (Int, String))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, let (code, body) = Self.responder?(url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return
        }
        let resp = HTTPURLResponse(url: url, statusCode: code, httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

// Settings accessors round-trip: every UserDefaults-backed property reads back
// what it stores, and the explicit value is restored afterwards.
extension AppSupportTests {
    func testSettingsAccessorRoundTrips() {
        let s = AppState.shared
        // Bool accessors (save → flip → assert → restore).
        let bools: [(get: () -> Bool, set: (Bool) -> Void)] = [
            ({ s.autoRestore }, { s.autoRestore = $0 }),
            ({ s.freeMarking }, { s.freeMarking = $0 }),
            ({ s.modernOrthography }, { s.modernOrthography = $0 }),
            ({ s.liveSpellCheck }, { s.liveSpellCheck = $0 }),
            ({ s.simpleTelex }, { s.simpleTelex = $0 }),
            ({ s.quickTelex }, { s.quickTelex = $0 }),
            ({ s.vniMode }, { s.vniMode = $0 }),
            ({ s.contextualEnglish }, { s.contextualEnglish = $0 }),
            ({ s.tapModifyEventInPlace }, { s.tapModifyEventInPlace = $0 }),
            ({ s.tapSkipSyntheticKeyUp }, { s.tapSkipSyntheticKeyUp = $0 }),
            ({ s.axSelectionReplace }, { s.axSelectionReplace = $0 }),
            ({ s.tapCascadeBreaker }, { s.tapCascadeBreaker = $0 }),
            ({ s.debugLogging }, { s.debugLogging = $0 }),
            ({ s.advancedFeatures }, { s.advancedFeatures = $0 }),
            ({ s.autoUpdateCheck }, { s.autoUpdateCheck = $0 }),
            ({ s.axPromptShown }, { s.axPromptShown = $0 }),
        ]
        for accessor in bools {
            let saved = accessor.get()
            accessor.set(!saved)
            XCTAssertEqual(accessor.get(), !saved)
            accessor.set(saved)
            XCTAssertEqual(accessor.get(), saved)
        }
        // String/scalar accessors.
        let lang = s.uiLanguage
        s.uiLanguage = "vi"; XCTAssertEqual(s.uiLanguage, "vi")
        s.uiLanguage = lang
        let v = s.lastNotifiedUpdateVersion
        s.lastNotifiedUpdateVersion = "9.9.9"
        XCTAssertEqual(s.lastNotifiedUpdateVersion, "9.9.9")
        s.lastNotifiedUpdateVersion = v
        XCTAssertFalse(VTLocalized("Close").isEmpty)   // localization lookup path
        _ = s.tapNativeFastPath
    }
}

// The key-ROUTING predicate shared by the IMKit controller and the terminal tap:
// which keys belong to the word (→ engine.feed) vs end it (→ boundary commit).
// Issue #28 (2026-07-27): VNI shipped working at the engine level but did nothing in
// the app because BOTH key paths gated on letters only, so every VNI digit was eaten
// as a word boundary ("a1" stayed "a1"). Pin the rule here.
final class WordKeyRoutingTests: XCTestCase {

    func testLettersAreAlwaysWordKeys() {
        for c in "abzABZ".utf8 {
            XCTAssertTrue(isWordKey(c, vniMode: false), "'\(Character(UnicodeScalar(c)))' must compose")
            XCTAssertTrue(isWordKey(c, vniMode: true))
        }
    }

    func testDigitsAreWordKeysOnlyInVNI() {
        for c in "0123456789".utf8 {
            XCTAssertFalse(isWordKey(c, vniMode: false), "a digit ends the word in Telex")
            XCTAssertTrue(isWordKey(c, vniMode: true), "a digit carries the diacritic in VNI")
        }
    }

    func testEverythingElseIsABoundaryInBothModes() {
        for c in " \t.,;:!?-_/\\[]{}()'\"@#$%^&*+=<>|~`".utf8 {
            XCTAssertFalse(isWordKey(c, vniMode: false))
            XCTAssertFalse(isWordKey(c, vniMode: true))
        }
    }
}

// Re-edit the word before the caret (experimental, opt-in): the two PURE pieces of the
// decision — which keys may trigger a read-back, and which trailing text counts as a
// re-editable word. The seeding itself is engine-side (TelexEngine.seed, round-trip
// checked there); the IMKit wiring needs a live client and is covered by hand.
final class ReEditWordTests: XCTestCase {

    func testOnlyModifierKeysTrigger() {
        for c in "sfrxjzwSFRXJZW".utf8 {
            XCTAssertTrue(TelexInputController.isDiacriticOnlyKey(c, vni: false),
                          "'\(Character(UnicodeScalar(c)))' is a Telex modifier")
        }
        // Ordinary letters — including the doublers a/e/o/d — must NOT trigger a read-back.
        for c in "abcdeghiklmnopqtuvy".utf8 {
            XCTAssertFalse(TelexInputController.isDiacriticOnlyKey(c, vni: false),
                           "'\(Character(UnicodeScalar(c)))' is a letter, not a modifier")
        }
        // VNI: the digits carry the diacritics, letters never do.
        for c in "0123456789".utf8 {
            XCTAssertTrue(TelexInputController.isDiacriticOnlyKey(c, vni: true))
        }
        for c in "sfrxjw".utf8 {
            XCTAssertFalse(TelexInputController.isDiacriticOnlyKey(c, vni: true),
                           "in VNI a letter is always literal")
        }
    }

    func testTrailingWordExtraction() {
        XCTAssertEqual(TelexInputController.trailingWord("xin chao toan"), "toan")
        XCTAssertEqual(TelexInputController.trailingWord("toan"), "toan")
        XCTAssertEqual(TelexInputController.trailingWord("Đường"), "Đường")
        XCTAssertEqual(TelexInputController.trailingWord("(hoa"), "hoa")
        // Stops at anything that is not a letter — no re-editable tail at all.
        XCTAssertNil(TelexInputController.trailingWord("mp3"))
        XCTAssertNil(TelexInputController.trailingWord("a-b-"))
        XCTAssertNil(TelexInputController.trailingWord("done "))
        XCTAssertNil(TelexInputController.trailingWord(""))
        XCTAssertNil(TelexInputController.trailingWord("x)"))
        // Longer than any syllable → not worth reading (the engine would refuse it).
        XCTAssertNil(TelexInputController.trailingWord("abcdefghijklmnop"))
    }
}

// The ⌫ guard: our tracked composition window may only be rewritten while the app's
// caret still agrees with it. Tester report 2026-07-27 (Chrome Web Store search box):
// the first ⌫ ate TWO characters and afterwards nothing typed showed up until a space —
// a React-controlled input had moved/re-rendered under the tracked range.
final class TrackedWindowFreshnessTests: XCTestCase {

    func testFreshOnlyWhenCaretSitsExactlyAtTheEndWithNoSelection() {
        XCTAssertTrue(TelexInputController.trackedWindowIsFresh(caret: 12, selectionLength: 0, expected: 12))
        // A selection (inline autocomplete suffix) would be swallowed by the rewrite.
        XCTAssertFalse(TelexInputController.trackedWindowIsFresh(caret: 12, selectionLength: 3, expected: 12))
        // Caret moved / field re-rendered — in either direction.
        XCTAssertFalse(TelexInputController.trackedWindowIsFresh(caret: 11, selectionLength: 0, expected: 12))
        XCTAssertFalse(TelexInputController.trackedWindowIsFresh(caret: 13, selectionLength: 0, expected: 12))
        // No caret at all → never rewrite blind.
        XCTAssertFalse(TelexInputController.trackedWindowIsFresh(caret: nil, selectionLength: 0, expected: 12))
        // Start of a field is a normal, fresh state.
        XCTAssertTrue(TelexInputController.trackedWindowIsFresh(caret: 0, selectionLength: 0, expected: 0))
    }
}

// Password fields must never be composed into. `IsSecureEventInputEnabled()` only covers
// apps that switch secure input on — a web <input type="password"> does not, and the
// `.emptyReset` strategy's U+202F placeholder then lands in the password as a stray
// character (field report 2026-07-27: "điền password thấy nó inject thêm 1-2 ký tự").
// The AX subrole is the signal; this pins its polarity, because a false POSITIVE would
// silently stop Vietnamese typing everywhere.
final class SecureFieldDetectionTests: XCTestCase {

    func testOnlyTheExplicitPasswordSubroleCounts() {
        XCTAssertTrue(SecureFieldDetector.isSecureSubrole("AXSecureTextField"))
        // Ordinary fields and every "we don't know" answer must read as NOT secure.
        for subrole in ["AXStandardWindow", "AXSearchField", "AXTextField", "", "AXUnknown"] {
            XCTAssertFalse(SecureFieldDetector.isSecureSubrole(subrole), "'\(subrole)' is not a password field")
        }
        XCTAssertFalse(SecureFieldDetector.isSecureSubrole(nil), "no subrole → compose as usual")
    }
}
