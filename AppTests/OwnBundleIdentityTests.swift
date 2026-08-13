import XCTest
@testable import VietTelex

// The app must recognize its OWN input source, whatever bundle id this build was
// installed under. `Scripts/dev-register.sh` remaps every id to a separate dev
// namespace (rule #4, docs/MACOS_IME_NOTES.md), and while the ship id was hardcoded
// in isVietTelexSelected() the dev build answered "VietTelex is not selected" about
// itself — so the TIS notification, deactivateServer and the per-key reconcile all
// put the tap DORMANT mid-word. Tester log 2026-08-13: "biết" in Terminal came out
// "biêts" (the tone key passed through raw during a dormant window), and ⌫ back to
// "bi" then `s` gave "bis" instead of "bí" (dormancy also resets the engine).
//
// Everything here drives `inputSourceIsOurs` through its explicit `own:` seam. A test
// that compared OwnBundle.id against Bundle.main would be tautological — both sides
// read the same property, and CI builds under the ship id, so re-hardcoding that
// literal would still pass. The prefix RULE is what these lock down.
final class OwnBundleIdentityTests: XCTestCase {

    private let ship = "com.viettelex.inputmethod.telex"
    private let dev = "com.tuanhm.inputmethod.telexdev"

    /// The regression itself: a dev build asking the SHIP prefix disowns its own input
    /// source; asking its own id recognizes it. The ship build is unaffected.
    func testDevBuildRecognizesItsOwnInputSource() {
        XCTAssertFalse(TelexInputController.inputSourceIsOurs(dev + ".vi", own: ship))
        XCTAssertTrue(TelexInputController.inputSourceIsOurs(dev + ".vi", own: dev))
        XCTAssertTrue(TelexInputController.inputSourceIsOurs(ship + ".vi", own: ship))
    }

    /// The bundle id itself and its `.vi` input mode both match; a sibling id that
    /// merely shares the namespace does not.
    func testInputSourceAndModeMatchButSiblingsDoNot() {
        XCTAssertTrue(TelexInputController.inputSourceIsOurs(ship, own: ship))
        XCTAssertTrue(TelexInputController.inputSourceIsOurs(ship + ".vi", own: ship))
        XCTAssertFalse(TelexInputController.inputSourceIsOurs(ship, own: dev))
    }

    func testForeignInputSourceDoesNotMatch() {
        XCTAssertFalse(TelexInputController.inputSourceIsOurs("com.apple.keylayout.ABC"))
        XCTAssertFalse(TelexInputController.inputSourceIsOurs("com.apple.keylayout.ABC", own: ship))
        XCTAssertFalse(
            TelexInputController.inputSourceIsOurs("com.apple.inputmethod.VietnameseIM.VietnameseTelex",
                                                   own: ship))
    }

    /// An empty prefix must match NOTHING. Bare `hasPrefix("")` is true for every id,
    /// which would report VietTelex selected while the user types in ABC and leave the
    /// tap composing Vietnamese over English.
    func testEmptyPrefixMatchesNothing() {
        XCTAssertFalse(TelexInputController.inputSourceIsOurs("com.apple.keylayout.ABC", own: ""))
        XCTAssertFalse(TelexInputController.inputSourceIsOurs(ship + ".vi", own: ""))
    }

    /// …and OwnBundle never hands one out, so the guard above is belt-and-braces.
    func testOwnBundleIDIsNeverEmpty() {
        XCTAssertFalse(OwnBundle.id.isEmpty)
    }
}
