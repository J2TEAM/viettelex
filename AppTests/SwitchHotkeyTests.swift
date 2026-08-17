import XCTest
@testable import VietTelex

// Hotkey chuyển bộ gõ chỉ-gồm-modifier (17/08/2026, tiếp nối issue #54). Máy nhận
// diện chord là hàm thuần tap-thread — pin đủ các kịch bản nhả/nhầm/ngắt ở đây vì
// sai một ca là hoặc chuyển bộ gõ giữa lúc user bấm shortcut, hoặc hotkey chết im.
final class SwitchHotkeyTests: XCTestCase {

    private let ctrlShift: CGEventFlags = [.maskControl, .maskShift]

    /// Diễn lại một chuỗi flagsChanged, trả về số lần fire.
    private func run(_ states: [CGEventFlags], target: CGEventFlags,
                     interruptAt: Int? = nil) -> Int {
        var r = ModifierChordRecognizer()
        var fires = 0
        for (i, f) in states.enumerated() {
            if i == interruptAt { r.disarm() }
            if r.note(flags: f, target: target) { fires += 1 }
        }
        return fires
    }

    func testCleanPressAndReleaseFiresOnce() {
        // ⌃ xuống → ⌃⇧ đủ bộ → nhả sạch: đúng MỘT lần fire (lúc nhả).
        XCTAssertEqual(run([[.maskControl], ctrlShift, []], target: ctrlShift), 1)
        // Nhả từng phím một (⌃⇧ → ⇧ → rỗng): vẫn một lần — fire ở bước nhả đầu,
        // các bước sau không armed nữa.
        XCTAssertEqual(run([ctrlShift, [.maskShift], []], target: ctrlShift), 1)
    }

    func testTypingWhileHeldCancels() {
        // ⌃⇧ đang giữ mà gõ phím (disarm chen giữa) rồi nhả → shortcut thật, 0 fire.
        XCTAssertEqual(run([ctrlShift, []], target: ctrlShift, interruptAt: 1), 0)
    }

    func testAddingAThirdModifierCancels() {
        // ⌃⇧ rồi thêm ⌘ (thành chord khác) rồi nhả hết: không fire lần nào —
        // kể cả khi đường nhả có đi ngang qua đúng tổ hợp ⌃⇧.
        XCTAssertEqual(run([ctrlShift, [.maskControl, .maskShift, .maskCommand], []],
                           target: ctrlShift), 0)
        // Nhưng nếu SAU đó user lại bấm ⌃⇧ sạch thì phải fire lại bình thường.
        XCTAssertEqual(run([ctrlShift, [.maskControl, .maskShift, .maskCommand], [],
                            ctrlShift, []], target: ctrlShift), 1)
    }

    func testWrongComboNeverFires() {
        XCTAssertEqual(run([[.maskCommand, .maskShift], []], target: ctrlShift), 0)
        XCTAssertEqual(run([[.maskShift], []], target: ctrlShift), 0)
    }

    func testIrrelevantFlagsAreIgnored() {
        // Caps Lock / bit device-dependent không được phá so khớp: ⌃⇧ + capsLock
        // đang bật vẫn là ⌃⇧.
        let withCaps: CGEventFlags = [.maskControl, .maskShift, .maskAlphaShift]
        XCTAssertEqual(run([withCaps, [.maskAlphaShift]], target: ctrlShift), 1)
    }

    func testChoiceMapping() {
        XCTAssertEqual(SwitchHotkey.targetFlags(for: "ctrl-shift"), [.maskControl, .maskShift])
        XCTAssertEqual(SwitchHotkey.targetFlags(for: "opt-shift"), [.maskAlternate, .maskShift])
        XCTAssertEqual(SwitchHotkey.targetFlags(for: "cmd-shift"), [.maskCommand, .maskShift])
        XCTAssertNil(SwitchHotkey.targetFlags(for: "off"))
        XCTAssertNil(SwitchHotkey.targetFlags(for: "rác-từ-bản-cũ"))   // không crash, coi như tắt
    }

    func testLastOtherSourceOnlyRemembersNonVietTelex() {
        SwitchHotkey.noteSelection(isVietTelex: false, currentID: "com.apple.keylayout.ABC")
        XCTAssertEqual(SwitchHotkey.lastOtherSourceID, "com.apple.keylayout.ABC")
        // Chọn VietTelex không được ghi đè đích quay-về.
        SwitchHotkey.noteSelection(isVietTelex: true, currentID: "com.viettelex.inputmethod.telex.vi")
        XCTAssertEqual(SwitchHotkey.lastOtherSourceID, "com.apple.keylayout.ABC")
        // nil id (TIS trả lỗi thoáng qua) không xoá mất đích cũ.
        SwitchHotkey.noteSelection(isVietTelex: false, currentID: nil)
        XCTAssertEqual(SwitchHotkey.lastOtherSourceID, "com.apple.keylayout.ABC")
    }
}
