import XCTest
@testable import VietTelex

// Tính toàn vẹn của FILE DỮ LIỆU typing-modes.yml (bundled resource) — tầng mà
// không test nào khoá trước ngày 30/07/2026. Hôm đó comment viết CÙNG DÒNG với
// rule (`dev.warp.Warp: tap  # kênh dev`) làm 2 rule Warp mới ra mode
// "tap  # kênh dev" → AppMode(rawValue:) nil → AppState bỏ im lặng (chỉ còn một
// dòng fault trong log), Warp gõ như app thường và mất dấu trong terminal.
// Parser cố ý KHÔNG cắt comment cuối dòng (giá trị gõ tắt được chứa "#" — xem
// ShortcutImporterTests.testInlineCommentIsNotStripped), nên hàng rào duy nhất
// khả thi là test phía dữ liệu: mọi rule trong file phải ra một AppMode hợp lệ.
final class BundledTypingModesTests: XCTestCase {

    /// Bảng rule ĐÃ SHIP (resource trong app bundle), không phải file trong repo.
    private func bundledRules() throws -> [String: String] {
        let bundle = Bundle(for: TelexInputController.self)
        guard let url = bundle.url(forResource: "typing-modes", withExtension: "yml"),
              let data = try? Data(contentsOf: url),
              let dict = ShortcutImporter.parse(data)
        else { throw XCTSkip("bundled typing-modes.yml unreadable") }
        return dict
    }

    /// Các dòng rule thô trong file (bỏ comment/dòng trống) — dùng để đối chiếu với
    /// số rule parser thực sự nhận.
    private func rawRuleLines() throws -> [(key: String, value: String)] {
        let bundle = Bundle(for: TelexInputController.self)
        guard let url = bundle.url(forResource: "typing-modes", withExtension: "yml"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { throw XCTSkip("bundled typing-modes.yml unreadable") }
        return text.split(separator: "\n").compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix(";"),
                  !line.hasPrefix("//"), let colon = line.firstIndex(of: ":") else { return nil }
            return (String(line[..<colon]).trimmingCharacters(in: .whitespaces),
                    String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
        }
    }

    // MARK: Bug 30/07/2026 — comment cùng dòng giết 2 rule Warp

    func testWarpChannelsAllResolveToTap() throws {
        // Warp là terminal → lời hứa cốt lõi "gõ tiếng Việt trong terminal".
        // 3 bundle id, cùng một app, 3 kênh phát hành.
        for id in ["dev.warp.Warp-Stable", "dev.warp.Warp", "dev.warp.Warp-Preview"] {
            XCTAssertEqual(try bundledRules()[id], "tap", "\(id) thiếu/hỏng trong typing-modes.yml")
            XCTAssertTrue(AppState.builtInFallbackApps.contains(id),
                          "\(id) không vào builtInFallbackApps — mode bị parse thành rác?")
            XCTAssertEqual(AppState.shared.autoResolvedMode(id), .tap, id)
        }
    }

    func testEveryParsedRuleIsAValidNonAutoMode() throws {
        // Đây là hàng rào chống "unknown mode": AppState.builtInRules bỏ im lặng mọi
        // value không map được sang AppMode, và `auto` cũng bị bỏ (auto = không có
        // rule). Nếu ai lại thêm comment cùng dòng, hoặc gõ sai tên mode
        // ("inplace", "Tap", "ax-detect"), test này chỉ ngay ra dòng nào.
        for (id, raw) in try bundledRules() {
            guard let mode = AppState.AppMode(rawValue: raw) else {
                return XCTFail("typing-modes.yml: mode không hợp lệ \(id) → \"\(raw)\"")
            }
            XCTAssertNotEqual(mode, .auto, "\(id): 'auto' không phải rule — hãy bỏ dòng này")
        }
    }

    func testEveryParsedRuleLandsInItsAppStateSet() throws {
        // builtInIDs() phân hoạch bảng rule theo mode; nếu một mode mới được thêm vào
        // file mà AppState chưa có set tương ứng thì rule "im lặng không có tác dụng".
        for (id, raw) in try bundledRules() {
            guard let mode = AppState.AppMode(rawValue: raw) else { continue }
            switch mode {
            case .tap:         XCTAssertTrue(AppState.builtInFallbackApps.contains(id), id)
            case .inPlace:     XCTAssertTrue(AppState.builtInInPlaceApps.contains(id), id)
            case .marked:      XCTAssertTrue(AppState.markedTextApps.contains(id), id)
            case .passthrough: XCTAssertTrue(AppState.builtInPassthroughApps.contains(id), id)
            case .axDetect, .emptyReset:
                XCTAssertTrue(AppState.builtInSpecialApps.contains(id), id)
            case .selection:
                // 12 rule `selection` (JetBrains/Android Studio) từng là DỮ LIỆU CHẾT —
                // không ai đọc builtInIDs(.selection) (phát hiện 31/07/2026, fix cùng
                // ngày: selectionAlwaysApps). Giờ chúng phải vào builtInSpecialApps.
                XCTAssertTrue(AppState.builtInSpecialApps.contains(id), id)
            case .auto:        XCTFail("\(id): auto")
            }
        }
    }

    func testSelectionRulesAreLiveAndEmitPlainSelection() throws {
        // Đối xứng của bug "dead data" 31/07/2026: IDE khai `selection` phải được
        // routing công nhận là .selection unconditional (autocomplete của JetBrains
        // là POPUP, không phải inline selection) và emit Shift+Left thuần —
        // KHÔNG rơi vào dance U+202F của browser per-field.
        let selectionIDs = try bundledRules().filter { $0.value == "selection" }.keys.sorted()
        XCTAssertFalse(selectionIDs.isEmpty, "file không còn rule selection — cập nhật test")
        for id in selectionIDs {
            XCTAssertEqual(AppState.shared.autoResolvedMode(id), .selection, id)
            XCTAssertEqual(AppState.shared.selectionEmitMode(id), .selection, id)
        }
    }

    // MARK: Đặc tả hiện trạng — cap 32 ký tự của ShortcutImporter

    func testLongBundleIDsSurviveTheKeyCap() throws {
        // Cap key của parser từng là 32 (dành cho bảng GÕ TẮT) và âm thầm giết 3 rule
        // bundle-id dài — phát hiện 31/07/2026, fix cùng ngày (cap 64). Pin cả hai
        // phía: 3 id dài phải CÓ trong bảng, và cap 64 vẫn chặn key rác siêu dài.
        let rules = try bundledRules()
        for id in ["com.apple.SafariTechnologyPreview",
                   "org.mozilla.firefoxdeveloperedition",
                   "com.citrix.receiver.icaviewer.mac"] {
            XCTAssertNotNil(rules[id], "\(id) bị parser bỏ rơi — cap key lại quá chặt?")
        }
        XCTAssertEqual(AppState.shared.autoResolvedMode("com.apple.SafariTechnologyPreview"), .axDetect)
        XCTAssertEqual(AppState.shared.autoResolvedMode("org.mozilla.firefoxdeveloperedition"), .axDetect)
        XCTAssertEqual(AppState.shared.autoResolvedMode("com.citrix.receiver.icaviewer.mac"), .passthrough)
        let junk = "k" + String(repeating: "x", count: 80) + ": tap\n"
        XCTAssertNil(ShortcutImporter.parse(junk.data(using: .utf8)!)?[String(junk.dropLast(6))])
    }

    func testNoRuleLineIsLostForAnyOtherReason() throws {
        // Mọi dòng rule phải đến được bảng, TRỪ đúng các key bị cap 32 ký tự ở trên.
        // Bắt các kiểu mất dòng khác: key rỗng, value rỗng, trùng key (dict thu gọn).
        let raw = try rawRuleLines()
        let expected = Set(raw.filter { $0.key.count <= 64 }.map(\.key))
        let parsed = Set(try bundledRules().keys)
        XCTAssertEqual(parsed, expected, "rule bị mất hoặc thêm khi parse")
        XCTAssertEqual(raw.filter { $0.key.count <= 64 }.count, expected.count,
                       "có bundle id khai báo trùng trong typing-modes.yml")
    }
}

// Round-trip của UpdateCheck.pendingUpdateVersion (Updater.swift, 1.4.22): tin
// "có bản mới" phải sống qua lần relaunch giữa lúc auto-check phát hiện và lúc
// user mở tab Giới thiệu, và phải được XOÁ sau khi cài xong (nếu không tab About
// nag mãi một phiên bản đã cài). Lưu trong suite settings — dưới XCTest suite này
// đã được isolate (AppState.settingsSuiteName), nên test không đụng cấu hình thật.
final class PendingUpdateVersionTests: XCTestCase {

    private var saved: String?

    override func setUp() {
        super.setUp()
        saved = UpdateCheck.pendingUpdateVersion
    }

    override func tearDown() {
        UpdateCheck.pendingUpdateVersion = saved
        super.tearDown()
    }

    func testRoundTripAndClear() {
        UpdateCheck.pendingUpdateVersion = "1.9.9"
        XCTAssertEqual(UpdateCheck.pendingUpdateVersion, "1.9.9")
        // nil → xoá hẳn (setter ghi "" ; getter phải coi "" là nil, chứ không phải
        // một phiên bản tên rỗng — đó là lý do có `flatMap { $0.isEmpty ? nil : $0 }`).
        UpdateCheck.pendingUpdateVersion = nil
        XCTAssertNil(UpdateCheck.pendingUpdateVersion)
        // Ghi đè phiên bản mới hơn: giá trị sau thắng, không cộng dồn.
        UpdateCheck.pendingUpdateVersion = "1.4.23"
        UpdateCheck.pendingUpdateVersion = "1.4.24"
        XCTAssertEqual(UpdateCheck.pendingUpdateVersion, "1.4.24")
    }

    func testStoredInIsolatedSettingsSuiteUnderTests() {
        // Cùng suite AppState dùng, và dưới XCTest suite đó là suite test riêng —
        // pin để không ai vô tình đổi UpdateCheck sang UserDefaults.standard
        // (sẽ ghi vào cấu hình máy dev mỗi lần chạy test, bug 30/07/2026).
        XCTAssertEqual(AppState.settingsSuiteName, "com.viettelex.settings.tests")
        UpdateCheck.pendingUpdateVersion = "9.9.9"
        let suite = UserDefaults(suiteName: AppState.settingsSuiteName)
        XCTAssertEqual(suite?.string(forKey: "pendingUpdateVersion"), "9.9.9")
    }
}

// Probe pair (SyntheticKeyboard.postProbe) từ 30/07/2026 được stamp() như mọi post
// site khác: hai CGEvent tạo liền nhau có thể nhận mach-time BẰNG NHAU, và window
// server đảo thứ tự event cùng timestamp → up trước down = phím kẹt logic trong
// app theo dõi key state. Khoá bất biến "stamp tăng NGẶT".
final class SyntheticStampTests: XCTestCase {

    func testConsecutiveStampsAreStrictlyIncreasing() throws {
        guard let src = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
        else { throw XCTSkip("không tạo được CGEvent trong môi trường test") }
        SyntheticKeyboard._testStamp(down)
        SyntheticKeyboard._testStamp(up)
        XCTAssertGreaterThan(up.timestamp, down.timestamp,
                             "up phải có stamp lớn hơn down, nếu không window server đảo cặp probe")
    }

    func testStampsStayIncreasingAcrossABurst() throws {
        guard let src = CGEventSource(stateID: .hidSystemState) else {
            throw XCTSkip("không tạo được CGEventSource trong môi trường test")
        }
        var previous: CGEventTimestamp = 0
        for i in 0..<50 {
            guard let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: i % 2 == 0) else {
                throw XCTSkip("không tạo được CGEvent trong môi trường test")
            }
            SyntheticKeyboard._testStamp(e)
            XCTAssertGreaterThan(e.timestamp, previous, "stamp thứ \(i) không tăng")
            previous = e.timestamp
        }
    }
}
