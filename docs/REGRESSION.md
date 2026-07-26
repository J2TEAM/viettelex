# VietTelex — Regression suite (độ chính xác)

Bộ test đối chiếu engine với **`telex_test_suite.csv`** (9.091 ca hợp lệ, bundled trong
`TelexCore/Tests/TelexCoreTests/Resources/`): từ tiếng Việt, từ tiếng Anh, và các
chuỗi phím nhập nhằng giữa hai thứ tiếng.

```bash
cd TelexCore && swift test --filter SuiteRegression
```

Harness (`SuiteRegressionTests.swift`) replay đúng như controller thật: chữ cái thì
compose, mọi ký tự khác (space, số, dấu câu) là **word boundary** → commit từ rồi
in ký tự đó. Nhờ vậy `ipv4`, `vieejt-nam`, `xin chaof!` đều round-trip đúng.
Cài đặt khi đo: `liveSpellCheck` ON (mặc định app), `freeMarking` OFF (xem
*Ghi chú* cuối trang).

## 4 bucket

| Bucket | Nghĩa | Ngưỡng |
|---|---|---|
| `transform` | Từ **Việt** phải ra đúng dạng có dấu (`vieejt` → việt) | **100%, exact** — hỏng 1 ca là fail build |
| `keep_as_typed` | Từ **Anh** engine không transform → phải giữ nguyên | **100%, exact** |
| `restore_raw` | Từ **Anh** BỊ transform → boundary phải khôi phục chuỗi phím gốc | **floor** (không được tụt) |
| `ambiguous_needs_context` | Compose ra âm tiết Việt hợp lệ NHƯNG chuỗi phím cũng là từ Anh (`his` → hí) — chỉ context (từ trước là tiếng Anh) mới lật được | **floor** |

Hai bucket tiếng Anh là **aspirational**: engine không mang từ điển tiếng Anh đầy
đủ (xem *Vì sao không 100%*), nên chốt sàn thay vì đòi tuyệt đối. Cải thiện được
thì nâng sàn ngay trong test.

## Kết quả

| Ngày | Version | transform | keep_as_typed | restore_raw | ambiguous (có context) | Ghi chú |
|---|---|---|---|---|---|---|
| 2026-07-25 | 1.4.16-dev | 400/400 | 362/362 | 6.790/7.282 (93,2%) | 632/1.047 (60,4%) | baseline sau khi chuẩn hoá harness theo boundary + mở rộng whitelist context |
| 2026-07-25 | 1.4.16-dev | 400/400 | 362/362 | 6.803/7.282 (93,4%) | 632/1.047 | fix free-marking bóp méo dù có cancel (`excess` → êcs) |
| 2026-07-26 | 1.4.16-dev | **400/400** | **362/362** | **7.212/7.282 (99,0%)** | **632/1.047** | luật hình dạng tone-cancel + refresh bảng collision (438 → 498 từ) |

Latency không đổi qua đợt 2026-07-26 (release build, cùng máy): **0,135 µs/phím**
(Việt) / 0,148 (Anh) / 0,008 (passthrough) — nằm trong dao động run-to-run của
[`BENCHMARKS.md`](BENCHMARKS.md). Bộ nhớ thêm: 3 Int trong parse state; tra từ điển
chỉ chạy ở **boundary của từ có cancel**, không nằm trên hot path.

## Đợt 2026-07-26: nhóm "tone-cancel ăn mất chữ"

Nhóm lỗi lớn nhất còn lại của `restore_raw`: từ tiếng Anh có **phụ âm-thanh gấp
đôi** (`ss ff rr xx jj`) — phím 1 bỏ dấu, phím 2 huỷ dấu và rơi mất 1 chữ:
`office` → ofice, `possess` → posess, `current` → curent.

Không thể chỉ "cancel thì luôn giữ nguyên": người dùng cũng **cố ý** gõ phím đôi
để escape (`gooogle` → google, `DDDR` → DDR, `hoass` → hoas). Hai tín hiệu cấu
trúc phân biệt được, **không cần từ điển**:

| Dạng cancel | Ví dụ | Quyết định |
|---|---|---|
| MARK doubler (`aaa` `ooo` `ddd` `ww`) — ở bất kỳ đâu | `gooogle` → google · `DDDR` → DDR | **GIỮ** (escape thật) |
| TONE key, **kề nhau + cuối từ** | `iss` → is · `aff` → af · `hoass` → hoas | **GIỮ** (escape thật) |
| TONE key **giữa từ** (còn chữ gõ sau) | `office` · `possess` · `necessity` | **RESTORE** raw (trừ khi composed là từ Anh: `Deffault` → Default) |
| TONE key **vươn ngược** (phím thanh bị huỷ nằm cách xa) | `hosts` · `asks` · `discs` · `buses` | **RESTORE** raw |

Nguyên tắc: escape thật **luôn** là phím đôi kề nhau ở cuối từ; cancel giữa từ
hoặc vươn ngược là phụ âm đôi tự nhiên của tiếng Anh → từ đã mất chữ.
Chi tiết trong `shouldRestoreRaw()` (`TelexEngine.swift`), golden test
`testToneCancelShapeRestoresEnglishWithoutDict`.

Kèm theo: `gen-english` giờ **monotone** — bảng sinh ra là HỢP với bảng đang ship
(luật mới cứu được từ nào thì vẫn giữ entry, vì cài đặt không mặc định như tắt bỏ
dấu tự do / Simple Telex có thể vẫn cần), cộng 32 từ Anh chọn tay còn miss
(`ghost`, `nose`, `trips`, `tariff`…). Bảng: 438 → 498 từ (~vài chục KB).

## Vì sao không 100%

**`restore_raw` — 70/7.282 ca còn lại (1,0%), đều là "dictionary-only":**

- **Protect-list**: chuỗi phím tiếng Anh trùng ĐÚNG cách gõ Telex của một từ Việt
  thật → **tiếng Việt luôn thắng** (`won` = ươn, `worst` = ướt, `zoo` = zô,
  `gif` = gì). Chính sách, không phải bug.
- **Viết tắt / tên riêng**: `ross`, `ieee`, `usps`, `nginx`, `ddr`, `isp` — không
  từ điển nào phủ, và thêm vào sẽ nuốt cách gõ tiếng Việt.
- **Token 2–3 chữ trong chuỗi symbol**: `/usr/local/bin`, `os.path`, `arr[i]`,
  `MAX_SIZE` — mảnh `us`, `os`, `arr`, `max` compose thành âm tiết Việt hợp lệ.

**`ambiguous_needs_context` — 632/1.047 (1.047 dòng = 344 từ distinct):**

| Sub-case | Từ distinct | Ý nghĩa |
|---|---|---|
| `ctx_fixes` | 162 | Sai khi đứng riêng, **đúng khi trong mạch tiếng Anh** — feature làm việc |
| `ok_both` | 49 | Đã restore sẵn, không cần context |
| `ctx_misses` | 133 | Engine giữ tiếng Việt, không restore |
| `ctx_breaks` | **0** | Context chưa làm hỏng ca nào |

Toàn bộ 133 ca `ctx_misses` là những dòng **chính suite ghi chú `never`** ("restore
sẽ làm từ Việt KHÔNG THỂ GÕ ĐƯỢC NỮA" — `bar` = bả, `car` = cả, `box` = bõ,
`bus` = bú, `max` = mã, `moon` = môn, `own` = ơn, `queen` = quên), tức cột
`expected` của suite tự mâu thuẫn với note của nó. Không có ca nào suite nói *nên*
restore mà engine bỏ sót → phần thiếu là **tranh chấp chính sách Việt-vs-Anh**, không
phải lỗi phủ context.

Bảng đánh giá tay cho nhóm ambiguous (mỗi từ distinct 1 dòng: output có/không
context, cờ whitelist/collision, note gốc của suite, mức ưu tiên review) sinh theo
yêu cầu — không commit vào repo vì là artifact review, không phải nguồn sự thật.

## Ghi chú

- **`freeMarking` OFF khi đo**: bỏ dấu tự do reach-back rất mạnh, trong kiểu replay
  từng phím thô của harness nó bóp méo từ Anh nhiều nguyên âm đôi (`excess` → êcs)
  — không phản ánh cách gõ thật, và sẽ làm *thấp giả* tỉ lệ restore. Vài dòng
  multi_path mà nó fix không đáng đổi.
- **18 dòng non-defect đã bị gỡ khỏi suite**: suite-wrong (`giaj` → giạ, `uow` → uơ),
  undefined_behavior (expected `?`), lựa chọn spec/mixed-case (`ToAnS`), và một
  token hai âm tiết (`đôla`) — nhờ vậy bucket `transform` mới chốt được exact 100%.
- Suite gán mỗi biến thể hoa/thường là một dòng riêng (`ROSS` / `Ross` / `ross`),
  nên số dòng luôn lớn hơn số từ distinct khoảng 3×.
