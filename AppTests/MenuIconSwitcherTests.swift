import XCTest
@testable import VietTelex

// Chọn biểu tượng menu bar (17/08/2026) — kỹ thuật ghi đè MenuIcon.pdf, chấp nhận
// gãy resource seal có chủ đích (đọc đầu MenuIconSwitcher.swift). Test pin phần
// thuần + sự tồn tại của cả ba resource, vì thiếu một file là switcher im lặng
// không làm gì (guard let url … else return false).
final class MenuIconSwitcherTests: XCTestCase {

    func testChoiceMapsToTheRightSourceFile() {
        XCTAssertEqual(MenuIconSwitcher.sourceName(for: "vt"), "MenuIcon1")
        XCTAssertEqual(MenuIconSwitcher.sourceName(for: "star"), "MenuIcon2")
        // Giá trị lạ (settings hỏng / bản cũ hơn) rơi về mặc định, không crash.
        XCTAssertEqual(MenuIconSwitcher.sourceName(for: "gibberish"), "MenuIcon1")
        XCTAssertEqual(MenuIconSwitcher.defaultChoice, "vt")
    }

    func testAllThreeIconResourcesShipInTheBundle() {
        // MenuIcon.pdf = đang hoạt động (Info.plist trỏ tới), MenuIcon1 = bản gốc
        // để quay lại, MenuIcon2 = sao 5 cánh. Thiếu cái nào là tính năng chết im.
        let bundle = Bundle(for: TelexInputController.self)
        for name in ["MenuIcon", "MenuIcon1", "MenuIcon2"] {
            let url = bundle.url(forResource: name, withExtension: "pdf")
            XCTAssertNotNil(url, "\(name).pdf thiếu trong bundle")
            if let url, let data = try? Data(contentsOf: url) {
                XCTAssertTrue(data.starts(with: Array("%PDF".utf8)), "\(name).pdf không phải PDF")
            }
        }
    }

    func testFreshBundleShipsWithTheDefaultIconActive() {
        // Bản build sạch: MenuIcon.pdf phải LÀ MenuIcon1.pdf (byte-identical) — nếu
        // lệch thì hoặc quên đồng bộ khi đổi icon mặc định, hoặc build script đã
        // chạm vào file active.
        let bundle = Bundle(for: TelexInputController.self)
        guard let active = bundle.url(forResource: "MenuIcon", withExtension: "pdf")
                .flatMap({ try? Data(contentsOf: $0) }),
              let vt = bundle.url(forResource: "MenuIcon1", withExtension: "pdf")
                .flatMap({ try? Data(contentsOf: $0) }) else {
            return XCTFail("thiếu resource")
        }
        XCTAssertFalse(MenuIconSwitcher.needsApply(active: active, source: vt),
                       "MenuIcon.pdf trong bản build không khớp MenuIcon1.pdf")
    }

    func testNeedsApplyIsAPureByteCompare() {
        let a = Data("%PDF-a".utf8), b = Data("%PDF-b".utf8)
        XCTAssertTrue(MenuIconSwitcher.needsApply(active: a, source: b))
        XCTAssertFalse(MenuIconSwitcher.needsApply(active: a, source: a))
    }
}
