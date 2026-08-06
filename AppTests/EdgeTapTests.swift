import XCTest
@testable import VietTelex

// EDGE-TAP (06/08/2026): từ neo ở offset 0 trong app PIN TAY In-place đi kênh
// synthetic ⌫-retype thay vì insertText. Field report: Discord pin In-place gõ
// ổn TRỪ chữ đầu message — "cos" → "coó". Slate/Lexical không map được
// replacementRange bắt đầu ở biên block nên APPEND thay vì replace; trick
// "space ở đầu" của maintainer xác nhận cơ chế (đẩy từ khỏi offset 0 là hết).
// Kênh synthetic là kênh duy nhất editor tôn trọng ở vị trí đó.
final class EdgeTapTests: XCTestCase {

    func testOnlyManualInPlacePinAtOffsetZeroWhileTrusted() {
        XCTAssertTrue(TelexInputController.edgeTapEligible(manualInPlace: true, caret: 0, trusted: true))
    }

    func testMidFieldWordStaysInPlace() {
        // Từ thứ hai trở đi (caret > 0) giữ nguyên in-place — đúng scope: user
        // xác nhận giữa dòng ổn, và synthetic hóa toàn bộ sẽ thành tap mode luôn.
        XCTAssertFalse(TelexInputController.edgeTapEligible(manualInPlace: true, caret: 3, trusted: true))
    }

    func testUnpinnedAppsNeverEdgeTap() {
        // App in-place built-in (TextEdit, Notes) honor offset 0 — không cần và
        // không được synthetic hóa chữ đầu (flicker vô ích).
        XCTAssertFalse(TelexInputController.edgeTapEligible(manualInPlace: false, caret: 0, trusted: true))
    }

    func testUntrustedFallsBackToPlainInPlace() {
        // Không có Trợ năng thì không post synthetic được — từ đầu chịu bug cũ
        // thay vì mất chữ (SyntheticKeyboard.apply sẽ drop cả edit nếu cứ gọi).
        XCTAssertFalse(TelexInputController.edgeTapEligible(manualInPlace: true, caret: 0, trusted: false))
    }

    func testNoCaretReadMeansNoEdgeTap() {
        // App không báo caret (một số Electron): không chứng minh được offset 0
        // → giữ đường per-op selectedRange như cũ.
        XCTAssertFalse(TelexInputController.edgeTapEligible(manualInPlace: true, caret: nil, trusted: true))
    }
}
