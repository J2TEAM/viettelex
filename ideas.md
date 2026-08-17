# Ideas — backlog ý tưởng

Ý tưởng chưa cam kết làm, xếp theo giá trị ước lượng giảm dần. Mỗi mục ghi đủ
ngữ cảnh để quay lại sau vài tháng vẫn hiểu vì sao nó nằm đây.

## 1. Injection Test tự verify (tự chẩn đoán chế độ gõ cho app lạ)

Một mục trong tab Thử nghiệm: user focus vào ô nhập của app đang lỗi, bấm
"Chạy thử" — VietTelex tự gõ một chuỗi test qua **từng chế độ gõ** (in-place,
tap backspace, marked, selection, emptyReset), sau mỗi lượt đọc lại text qua
Accessibility, so sánh (chuẩn hoá Unicode), rồi hiện ma trận PASS/FAIL kèm
diff từng ký tự. Kết quả copy được vào clipboard để dán vào bug report.

Giá trị: biến vòng lặp "tester tả lỗi → maintainer đoán → build thử → chờ
verify" thành user tự chạy 30 giây và gửi về đúng chế độ hoạt động. Cũng chính
là dữ liệu để thêm rule vào `typing-modes.yml` không phải đoán.

Lưu ý khi làm: cần quyền AX; phải khôi phục nội dung field sau test (hoặc chỉ
chạy trong field trống); app có autosave/gửi-khi-Enter cần né phím nguy hiểm.

## 2. Forward-Delete trước chuỗi backspace cho Excel / Google Sheets

Lớp emptyReset hiện phá cell-autocomplete bằng U+202F. Kỹ thuật bổ sung cho ca
autocomplete đã kịp highlight suggestion SAU caret: gửi một **Forward Delete
trước** chuỗi backspace để xoá suggestion (suggestion là selection, không phải
text thật — đừng dùng Esc vì Esc huỷ cả edit session của cell). Điều kiện an
toàn: chỉ làm khi AX xác nhận sau caret không có text thật (nhớ tính selection
length vào "text sau caret"); AX đọc fail → mặc định coi là CÓ text thật và
bỏ qua — thà sót autocomplete còn hơn xoá nhầm chữ của user.

## 3. Detector "hai bộ gõ cùng chạy"

Một lớp bug report ma có nguồn gốc là máy user đang chạy song song bộ gõ khác
(OpenKey/EVKey nền, hoặc bật kèm Simple Telex của OS) — hai bên giành nhau sửa
text, triệu chứng nhìn như lỗi của mình. Rẻ: quét process/input source đã biết
(OpenKey, EVKey, GoTiengViet…) lúc khởi động + khi mở debug snapshot; nếu thấy
thì thêm dòng cảnh báo vào snapshot và status menu ("Đang có bộ gõ khác chạy:
OpenKey — tắt một trong hai"). Không tự tắt hộ, chỉ nêu tên.

## 4. Safari type-ahead từ Start Page

Ca đặc thù: đứng ở Start Page/New Tab của Safari gõ luôn — phím đi vào address
bar nhưng AX focus vẫn báo AXWindow/AXList (không có editable field nào focus).
Router per-field hiện tại sẽ không nhận ra đây là omnibox. Heuristic: trong
Safari, "không có editable field focused mà vẫn nhận phím" ⇒ xử như address
bar. Cần repro trước khi làm.

## 5. Test case cần thử (chưa chắc lỗi, đáng kiểm)

- **Office Online** (Word/Excel trên web): lớp editor web có thể drop ký tự đã
  chèn khi autosave normalize DOM — chữ gõ tay sống, chữ bộ gõ chèn mất. Thử
  trên cả Safari lẫn Chrome; nếu dính thì cùng họ với các rule WebView inPlace.
- **Telegram Web**: popup gợi ý emoji chặn keydown; lưu ý backspace có thể làm
  popup dismiss (side effect), nên nếu lỗi thì tap backspace chưa chắc là thuốc.
- **"Đ.T."** (viết tắt tên riêng có Đ + dấu chấm): kiểm auto-restore không phá.
- **Restore theo dấu câu cuối câu** (`,` `.` `!` `?`): xác nhận auto-restore
  chạy ở các boundary này y như space/Enter.

## 6. Window-Title Rules — lớp override cho user tự vá app lạ

Khi bảng `typing-modes.yml` phình: cho user tự thêm rule match theo bundle id
+ **window title** (contains/prefix/regex) để ép chế độ gõ, không phải chờ
release. Title-matching giải được lớp "web app trong browser bất kỳ" (Google
Docs, Office Online) bằng một rule thay vì rule per-browser. Đánh đổi: bề mặt
config lớn, dễ thành nơi user tự bắn vào chân — chỉ làm khi nhu cầu thật xuất
hiện nhiều trong issues.

## 7. Tiện ích ngoài phạm vi gõ (cân nhắc chiến lược, chưa chắc nên)

- **Undo bỏ dấu**: hotkey biến từ vừa chốt về raw keystrokes ("tiếng" →
  "tieesng") — hữu ích khi muốn giữ nguyên chuỗi phím gốc.
- **Convert bảng mã**: chọn text → chuyển Unicode ↔ TCVN3 ↔ VNI-Windows, đổi
  hoa/thường, xoá dấu. Phục vụ người làm việc với tài liệu cũ.
- **iCloud sync settings + gõ tắt** qua NSUbiquitousKeyValueStore (merge
  per-entry, có tombstone cho xoá).
- **Dịch nhanh selection** bằng hotkey (provider miễn phí + fallback chain).
  Xa phạm vi bộ gõ nhất — chỉ ghi lại cho đủ.

## Bài học vận hành (không phải feature — nhắc để giữ kỷ luật)

- **Mất config sau update** là bug mất trust nặng nhất với user bộ gõ; mỗi lần
  đổi schema settings phải có test migration.
- **Đổi default hành vi gõ trong bản update** sinh cả chùm report "nâng cấp
  xong gõ khác hẳn" — cân nhắc migrate giữ hành vi cũ cho user hiện hữu khi
  default mới thay đổi cách gõ diện rộng.
