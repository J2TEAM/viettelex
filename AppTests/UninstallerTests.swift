import XCTest
@testable import VietTelex

// Nút Gỡ cài đặt (tab Giới thiệu, 17/08/2026). Test pin các guard thuần — phần
// destructive (xoá file/disable source) không chạy trong test, nhưng các quyết
// định "được phép xoá gì" thì phải khoá chặt.
final class UninstallerTests: XCTestCase {

    func testOnlyTheInstalledBundleIsRemovable() {
        // Bản cài thật: xoá được.
        XCTAssertTrue(Uninstaller.bundleIsRemovable(
            "/Users/ai/Library/Input Methods/VietTelex.app"))
        // Dev build chạy từ DerivedData / build dir: TUYỆT ĐỐI không tự xoá —
        // bấm nhầm nút khi đang dev không được nuốt mất build product.
        XCTAssertFalse(Uninstaller.bundleIsRemovable(
            "/Users/ai/Library/Developer/Xcode/DerivedData/VietTelex-abc/Build/Products/Debug/VietTelex.app"))
        XCTAssertFalse(Uninstaller.bundleIsRemovable("/Applications/VietTelex.app"))
        XCTAssertFalse(Uninstaller.bundleIsRemovable(""))
    }

    func testSettingsPlistPathPointsAtTheRealSuite() {
        // Đường dẫn plist phải theo settingsSuiteName (dưới XCTest là suite .tests —
        // nghĩa là chạy test không bao giờ trỏ vào settings thật của máy dev).
        let url = Uninstaller.settingsPlistURL(home: URL(fileURLWithPath: "/Users/ai"))
        XCTAssertEqual(url.path,
                       "/Users/ai/Library/Preferences/\(AppState.settingsSuiteName).plist")
        XCTAssertTrue(AppState.settingsSuiteName.hasSuffix(".tests"),
                      "test host phải đang ở suite cách ly")
    }
}
