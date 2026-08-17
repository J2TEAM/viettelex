// MenuIconSwitcher.swift
// Cho user chọn biểu tượng bộ gõ trên menu bar (maintainer 17/08/2026, CHẤP NHẬN
// RỦI RO có chủ đích — đọc kỹ trước khi "sửa"):
//
// Icon menu bar là metadata tĩnh (tsInputModeMenuIconFileKey → MenuIcon.pdf) do
// TextInputMenuAgent đọc lúc login scan. Không có API đổi lúc chạy. Cách duy nhất
// đổi được là GHI ĐÈ MenuIcon.pdf trong bundle đã cài rồi khởi động lại máy.
//
// Hệ quả đã cân nhắc và chấp nhận:
//  • Niêm phong resource của chữ ký GÃY (`codesign --verify` → "a sealed resource
//    is missing or invalid"). App VẪN chạy và VẪN giữ quyền Trợ năng — designated
//    requirement của TCC chỉ ràng identifier + chứng chỉ team, không ràng resource
//    seal (đã đo 17/08). Nhưng từ lúc đó `spctl`/`codesign --verify` không còn dùng
//    được làm bằng chứng "bundle nguyên vẹn" khi chẩn đoán máy user nữa — nếu user
//    bật icon sao, hãy nhớ điều này khi đọc bug report.
//  • Copy app sang máy khác sẽ bị Gatekeeper chặn (quarantine bật lại, seal hỏng).
//  • SelfUpdater tráo NGUYÊN bundle mỗi lần cập nhật → icon quay về mặc định.
//    Vì vậy applyIfNeeded() chạy lại MỖI LẦN KHỞI ĐỘNG: sau update, lựa chọn của
//    user được ghi đè lại tự động (icon hiện lại sau lần login kế).
//
// UI ở tab Thử nghiệm có ghi chú rõ hai điều trên cho user.

import Foundation

enum MenuIconSwitcher {
    /// Giá trị lưu trong settings. "vt" = mặc định (chữ Vᴛ), "star" = sao 5 cánh.
    static let defaultChoice = "vt"

    /// File nguồn tương ứng với lựa chọn — cả hai đều được ship trong Resources,
    /// MenuIcon.pdf là file "đang hoạt động" mà Info.plist trỏ tới.
    static func sourceName(for choice: String) -> String {
        choice == "star" ? "MenuIcon2" : "MenuIcon1"
    }

    /// Chỉ ghi khi nội dung khác — khởi động bình thường (đã đúng icon) không được
    /// chạm vào bundle, để seal chỉ gãy khi user THẬT SỰ đổi icon.
    static func needsApply(active: Data, source: Data) -> Bool { active != source }

    /// Ghi đè MenuIcon.pdf theo lựa chọn hiện tại. Trả về true nếu CÓ ghi (tức icon
    /// sẽ đổi sau lần khởi động lại kế tiếp), false nếu đã đúng sẵn hoặc lỗi.
    @discardableResult
    static func applyIfNeeded(choice: String) -> Bool {
        let bundle = Bundle.main
        guard let activeURL = bundle.url(forResource: "MenuIcon", withExtension: "pdf"),
              let sourceURL = bundle.url(forResource: sourceName(for: choice), withExtension: "pdf"),
              let active = try? Data(contentsOf: activeURL),
              let source = try? Data(contentsOf: sourceURL),
              needsApply(active: active, source: source) else { return false }
        do {
            // Ghi atomic: TextInputMenuAgent chỉ đọc file này lúc login scan nên không
            // có race thật, nhưng một file ghi dở là icon vỡ vĩnh viễn cho tới lần đổi sau.
            try source.write(to: activeURL, options: .atomic)
            DebugLog.log("menu-icon: applied '\(choice)' (restart required to show)")
            Signposts.log.notice("menu-icon applied: \(choice, privacy: .public) — resource seal now broken by design")
            return true
        } catch {
            DebugLog.log("menu-icon: apply FAILED — \(error.localizedDescription)")
            return false
        }
    }
}
