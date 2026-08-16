import XCTest
@testable import VietTelex

// Heuristic của StickyInputSource (field report 15/08/2026: Word coi mỗi ô comment
// là một document → macOS "Automatically switch to a document's input source" rơi
// về bộ gõ mặc định ở từng ô). Giành lại CHỈ khi thay đổi không phải của user —
// mọi ca nghi ngờ đều phải nghiêng về KHÔNG giành (bài học ping-pong #32).
final class StickyInputSourceTests: XCTestCase {

    private let sec: UInt64 = 1_000_000_000
    private var now: UInt64 { 100 * sec }   // mốc tuỳ ý, đủ lớn hơn mọi cửa sổ

    private func reclaim(was: Bool = true, isNow: Bool = false,
                         chord: UInt64 = 0, menuClick: UInt64 = 0,
                         appChange: UInt64 = 0, reclaims: Int = 0) -> Bool {
        StickyInputSource.shouldReclaim(
            wasVietTelex: was, isVietTelexNow: isNow, nowNs: now,
            lastChordNs: chord, lastMenuBarClickNs: menuClick,
            lastAppChangeNs: appChange, recentReclaims: reclaims)
    }

    func testAutoSwitchAwayWithNoGestureReclaims() {
        // Ca Word: VietTelex đang chọn, ô comment mới → macOS đổi source, không có
        // dấu vết thao tác nào của user → giành lại.
        XCTAssertTrue(reclaim())
        // Gesture/app-change CŨ (ngoài cửa sổ) không chặn.
        XCTAssertTrue(reclaim(chord: now - 2 * sec, menuClick: now - 10 * sec,
                              appChange: now - 5 * sec))
    }

    func testUserGesturesSuppressReclaim() {
        // ⌃Space (hay hotkey custom nào cũng kèm modifier) ngay trước switch.
        XCTAssertFalse(reclaim(chord: now - sec / 2))
        // Click vào dải menu bar: cửa sổ 5s (user còn tìm item trong dropdown).
        XCTAssertFalse(reclaim(menuClick: now - 4 * sec))
    }

    func testAppSwitchIsMacOSPerAppMemoryNotOurs() {
        // Đổi app frontmost quanh lúc switch = per-app memory của macOS làm đúng
        // việc của nó (vd Flameshot giữ ABC) — không được giành.
        XCTAssertFalse(reclaim(appChange: now - sec))
    }

    func testOnlyLeavingVietTelexTriggers() {
        XCTAssertFalse(reclaim(was: false, isNow: false))   // ABC → ABC khác
        XCTAssertFalse(reclaim(was: false, isNow: true))    // ai đó chọn VietTelex
        XCTAssertFalse(reclaim(was: true, isNow: true))     // vẫn là mình
    }

    func testBreakerStopsAFight() {
        // App ép ASCII-capable mà mình không nhận diện được sẽ đổi lại ngay sau mỗi
        // lần giành — quá 2 lần trong cửa sổ thì bỏ cuộc thay vì ping-pong.
        XCTAssertTrue(reclaim(reclaims: StickyInputSource.breakerMax - 1))
        XCTAssertFalse(reclaim(reclaims: StickyInputSource.breakerMax))
    }

    // MARK: Kịch bản per-app memory (câu hỏi maintainer 15/08): app A = VietTelex,
    // app B = ABC (user tự đặt), từ app C quay lại app B → phải Ở NGUYÊN ABC.

    func testReturningToAppPinnedToABCStaysABC() {
        // Đường thuận: notification activate-app (C→B) tới TRƯỚC notification đổi
        // source — lastAppChangeNs tươi ngay lúc quyết định → không giành.
        let appChange = now - sec / 10                       // vừa đổi app 0.1s trước
        XCTAssertFalse(reclaim(was: true, isNow: false, appChange: appChange))
    }

    func testNotificationRaceIsCaughtByTheReverifyLayer() {
        // Đường race: TIS tới TRƯỚC NSWorkspace — lúc quyết định lastAppChangeNs còn
        // CŨ nên shouldReclaim nói "giành" nhầm…
        let staleAppChange = now - 60 * sec
        XCTAssertTrue(reclaim(was: true, isNow: false, appChange: staleAppChange))
        // …nhưng reclaim chỉ chạy sau reclaimDelayMs, và lúc re-verify thì
        // notification activate đã được xử lý (timestamp tươi) → lớp bảo hiểm chặn.
        let reverifyTime = now + UInt64(StickyInputSource.reclaimDelayMs) * 1_000_000
        let freshAppChange = now + 20 * 1_000_000            // activate xử lý 20ms sau TIS
        XCTAssertFalse(StickyInputSource.reverifyAllowsReclaim(
            nowNs: reverifyTime, lastChordNs: 0, lastMenuBarClickNs: 0,
            lastAppChangeNs: freshAppChange, recentReclaims: 0))
        // Đối chứng: không có app change nào (ca Word thật) thì re-verify cho qua.
        XCTAssertTrue(StickyInputSource.reverifyAllowsReclaim(
            nowNs: reverifyTime, lastChordNs: 0, lastMenuBarClickNs: 0,
            lastAppChangeNs: staleAppChange, recentReclaims: 0))
    }

    func testReverifyHonorsLateGesturesAndBreaker() {
        // Trong 150ms chờ, user kịp nhấn ⌃Space → re-verify phải nhường.
        let t = now
        XCTAssertFalse(StickyInputSource.reverifyAllowsReclaim(
            nowNs: t, lastChordNs: t - sec / 20, lastMenuBarClickNs: 0,
            lastAppChangeNs: 0, recentReclaims: 0))
        XCTAssertFalse(StickyInputSource.reverifyAllowsReclaim(
            nowNs: t, lastChordNs: 0, lastMenuBarClickNs: t - sec,
            lastAppChangeNs: 0, recentReclaims: 0))
        XCTAssertFalse(StickyInputSource.reverifyAllowsReclaim(
            nowNs: t, lastChordNs: 0, lastMenuBarClickNs: 0,
            lastAppChangeNs: 0, recentReclaims: StickyInputSource.breakerMax))
    }

    func testMenuBarStripDetection() {
        // Display chính: bounds (0,0,1728,1117), y=0 là MÉP TRÊN (toạ độ CGEvent).
        let main = { (_: CGPoint) -> CGRect? in CGRect(x: 0, y: 0, width: 1728, height: 1117) }
        XCTAssertTrue(StickyInputSource.isInMenuBarStrip(CGPoint(x: 900, y: 12), displayBounds: main))
        XCTAssertTrue(StickyInputSource.isInMenuBarStrip(CGPoint(x: 900, y: 44), displayBounds: main))
        XCTAssertFalse(StickyInputSource.isInMenuBarStrip(CGPoint(x: 900, y: 45), displayBounds: main))
        // Màn hình phụ đặt DƯỚI màn chính (origin.y > 0): dải bar tính theo minY của
        // display đó, không phải y toàn cục nhỏ.
        let below = { (_: CGPoint) -> CGRect? in CGRect(x: 0, y: 1117, width: 1920, height: 1080) }
        XCTAssertTrue(StickyInputSource.isInMenuBarStrip(CGPoint(x: 100, y: 1130), displayBounds: below))
        XCTAssertFalse(StickyInputSource.isInMenuBarStrip(CGPoint(x: 100, y: 1200), displayBounds: below))
        // Điểm ngoài mọi display (mid-drag, display vừa rút): không phải menu bar.
        XCTAssertFalse(StickyInputSource.isInMenuBarStrip(.zero, displayBounds: { _ in nil }))
    }
}
