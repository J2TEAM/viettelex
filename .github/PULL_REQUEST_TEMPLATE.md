<!-- Xoá phần nào không liên quan. Mục tiêu: reviewer hiểu được thay đổi mà không phải đọc hết diff. -->

## Thay đổi gì

<!-- Một hai câu: hành vi TRƯỚC → SAU. Nếu fix lỗi đã có issue: `Closes #NN`. -->

## Loại thay đổi

- [ ] Rule cơ chế gõ (`typing-modes.yml`)
- [ ] Engine / validator (`TelexCore/`)
- [ ] App: routing per-app, IMKit, CGEventTap, Settings UI (`App/Sources/`)
- [ ] Tài liệu (`docs/`, `README.md`, `BAO-LOI.md`)
- [ ] Khác:

## Đã test

- [ ] `cd TelexCore && swift test` xanh
- [ ] Có golden test cho hành vi mới trong `EngineTests.swift` (bắt buộc khi sửa engine)
- [ ] `swift test -c release --filter 'Benchmark|ZeroAllocation'` xanh — hot path không cấp phát heap
- [ ] Đã cài lên máy thật (`Scripts/dev-install.sh`) và gõ thử trong app bị ảnh hưởng, theo [`docs/checklist.md`](https://github.com/ptrinh/viettelex/blob/main/docs/checklist.md)

Máy đã test: <!-- ví dụ: macOS 26.1, MacBook Pro M2, VietTelex 1.5.10 -->

## Nếu PR thêm/sửa rule `typing-modes.yml`

- Bundle id: `` <!-- lấy bằng: osascript -e 'id of app "Tên app"' -->
- Mode chọn: `` — mode cũ (hoặc auto-probe) sai thế nào:
- [ ] Đã test cả **biên**, không chỉ giữa dòng: đầu dòng, đầu message/ô, giữa từ, `⌫` giữa từ
- [ ] Comment (nếu có) nằm **riêng một dòng** — parser không đọc được comment cùng dòng với rule

## Ghi chú cho reviewer

<!-- Ảnh/video nếu đụng UI. Chỗ nào bạn muốn được soi kỹ? Đánh đổi nào đã chọn? -->
