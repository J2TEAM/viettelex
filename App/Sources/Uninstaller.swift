// Uninstaller.swift
// Nút "Gỡ cài đặt" ở cuối tab Giới thiệu (maintainer 17/08/2026 — field request
// qua email: user gỡ khỏi Input Sources, khởi động lại máy mà app vẫn còn, không
// biết gỡ hẳn thế nào). Gỡ trọn gói: chuyển bàn phím về ABC, disable input source,
// xoá toàn bộ settings, xoá app bundle, rồi thoát process.
//
// Trình tự CÓ CHỦ ĐÍCH, đừng đảo:
//  1. Chọn ABC trước — để bàn phím user không chết giữa chừng khi source của mình
//     biến mất bên dưới.
//  2. TISDisableInputSource — bỏ khỏi enabled list ngay (không chờ login scan).
//  3. Xoá settings (persistent domain + file plist) — sau bước này AppState còn
//     cache in-memory nhưng process sắp chết nên vô hại.
//  4. Xoá app bundle — CHỈ khi nó thật sự nằm trong Input Methods (dev build chạy
//     từ DerivedData không được tự xoá build product).
//  5. exit(0). macOS không respawn được nữa (binary đã mất); dòng còn sót trong
//     picker biến mất sau lần đăng xuất/đăng nhập kế (registration sống theo
//     login scan — xem MACOS_IME_NOTES).

import AppKit
import Carbon.HIToolbox

enum Uninstaller {
    /// Bundle chỉ được phép tự xoá khi nằm trong Input Methods — chạy dev từ
    /// DerivedData/Xcode mà bấm nút này thì mọi thứ khác vẫn gỡ, riêng file build
    /// giữ lại. Tách thuần để test.
    static func bundleIsRemovable(_ path: String) -> Bool {
        path.contains("/Library/Input Methods/")
    }

    static func settingsPlistURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Preferences/\(AppState.settingsSuiteName).plist")
    }

    /// Chạy sau khi user đã xác nhận qua alert (UI lo phần hỏi). Trả về thông điệp
    /// tổng kết để UI hiện trước khi thoát.
    static func run() -> String {
        Signposts.log.notice("uninstall: user-confirmed, starting")
        // 1. Bàn phím về ABC trước khi rút thảm.
        _ = SwitchHotkey.selectInputSource(id: SwitchHotkey.fallbackOtherID)
        // 2. Best-effort disable — kể cả fail thì login scan sau khi bundle biến mất
        //    cũng dọn nốt.
        disableOwnInputSources()
        // 3. Settings: cả persistent domain lẫn file (removePersistentDomain là đủ
        //    về mặt defaults, xoá file cho sạch mắt người kiểm tra thủ công).
        UserDefaults.standard.removePersistentDomain(forName: AppState.settingsSuiteName)
        try? FileManager.default.removeItem(at: settingsPlistURL())
        // 4. App bundle.
        let bundleURL = Bundle.main.bundleURL
        var removedApp = false
        if bundleIsRemovable(bundleURL.path) {
            removedApp = (try? FileManager.default.removeItem(at: bundleURL)) != nil
        }
        DebugLog.log("uninstall: app removed=\(removedApp)")
        return removedApp
            ? VTLocalized("VietTelex has been removed. Log out and back in to clear it from the input source list.")
            : VTLocalized("Settings were removed, but the app file could not be deleted — drag it to the Trash from ~/Library/Input Methods.")
    }

    /// Disable mọi input source thuộc build này (kể cả bản dev id khác — cùng prefix).
    private static func disableOwnInputSources() {
        guard let list = TISCreateInputSourceList(nil, true)?
            .takeRetainedValue() as? [TISInputSource] else { return }
        for source in list {
            guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
            else { continue }
            let id = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
            if TelexInputController.inputSourceIsOurs(id) {
                TISDisableInputSource(source)
            }
        }
    }
}
