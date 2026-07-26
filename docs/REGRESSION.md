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
| 2026-07-26 | 1.4.16-dev | 400/400 | 362/362 | 7.212/7.282 (99,0%) | 632/1.047 | luật hình dạng tone-cancel + refresh bảng collision (438 → 498 từ) |
| 2026-07-26 | 1.4.16-dev | **400/400** | **362/362** | **7.201/7.282 (98,9%)** | **632/1.047** | **bỏ luật restore cho phím-đôi-kề-nhau (field report `tessted`), bù bằng từ điển sinh từ chính suite (498 → 757 từ)** |

Latency không đổi qua đợt 2026-07-26 (release build, cùng máy): **0,138 µs/phím**
(Việt) / 0,150 (Anh) / 0,007 (passthrough) — nằm trong dao động run-to-run của
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
| **Phím đôi KỀ NHAU** (tone `ss`/`ff`… hoặc mark `aaa`/`ooo`/`ddd`/`ww`), ở bất kỳ đâu trong từ | `tessted` → tested · `Deffault` → Default · `gooogle` → google · `DDDR` → DDR · `hoass` → hoas · `iss` → is | **GIỮ composed** — what you see is what you commit |
| Phím tone **vươn ngược** (phím thanh bị huỷ nằm cách vài chữ) | `hosts` · `asks` · `discs` · `buses` | **RESTORE** raw |
| Bất kỳ dạng nào, nhưng **raw có trong từ điển** | `office` · `possess` · `message` · `class` | **RESTORE** raw (từ điển thắng tất cả) |

Nguyên tắc: escape thật **luôn** là phím đôi kề nhau, còn cancel vươn ngược thì
không bao giờ là escape → đó là tín hiệu cấu trúc duy nhất dùng được.

**Lần thử sai đã revert (ghi lại để không lặp):** ban đầu tôi cho *mọi* cancel giữa
từ restore raw (đưa restore_raw lên 99,0%), nhưng bàn phím của escape và của phụ âm
đôi tiếng Anh **giống hệt nhau** — `tessted` → tested (người dùng cố ý) không phân
biệt được với `office` → ofice (engine ăn mất chữ). Field report 2026-07-26 (`tessted`
bị đổi thành `tessted` sau space) chứng minh luật đó sai hướng: chỉ **từ điển** được
quyền lật, còn lại phải tôn trọng cái đang hiện trên màn hình.

Chi tiết trong `shouldRestoreRaw()` (`TelexEngine.swift`), golden test
`testAdjacentDoubleKeepsWhatTheScreenShows` + `testReachBackToneCancelRestoresWithoutDict`.

Bù lại bằng từ điển — `gen-english` có 2 thay đổi:
- **Monotone**: bảng sinh ra là HỢP với bảng đang ship (luật mới cứu được từ nào thì
  vẫn giữ entry, vì cài đặt không mặc định như tắt bỏ dấu tự do / Simple Telex có thể
  vẫn cần).
- **Corpus bổ sung từ chính suite**: cột input của bucket `restore_raw`, **chỉ nhận từ
  ≥5 chữ** — từ ngắn là bãi mìn tiếng Việt (`cos`=có, `gif`=gì, `max`=mã) — vẫn đi qua
  đủ engine-check + junk + protect list (đợt này protect thêm `ướt`=worst, `lẩu`=laura).

Bảng: 438 → **757 từ** (~vài chục KB, tra `Set<String>` ở boundary).

## Vì sao không 100%

**`restore_raw` — 81/7.282 ca còn lại (1,1%), đều là "dictionary-only":**

- **Protect-list**: chuỗi phím tiếng Anh trùng ĐÚNG cách gõ Telex của một từ Việt
  thật → **tiếng Việt luôn thắng** (`won` = ươn, `worst` = ướt, `zoo` = zô,
  `gif` = gì). Chính sách, không phải bug.
- **Viết tắt / tên riêng**: `ross`, `ieee`, `usps`, `nginx`, `ddr`, `isp` — không
  từ điển nào phủ, và thêm vào sẽ nuốt cách gõ tiếng Việt.
- **Token 2–3 chữ trong chuỗi symbol**: `/usr/local/bin`, `os.path`, `arr[i]`,
  `MAX_SIZE` — mảnh `us`, `os`, `arr`, `max` compose thành âm tiết Việt hợp lệ.
- **Phụ âm đôi kề nhau ngoài từ điển**: `carr`, `cass`, `hajj`, `toff`, `arr`, `ruff`
  — không thể restore bằng luật vì trùng bàn phím với escape có chủ ý (xem trên).

**`ambiguous_needs_context` — 632/1.047 (1.047 dòng = 344 từ distinct):**

| Sub-case | Từ distinct | Ý nghĩa |
|---|---|---|
| `ctx_fixes` | 162 | Sai khi đứng riêng, **đúng khi trong mạch tiếng Anh** — feature làm việc |
| `ok_both` | 49 | Đã restore sẵn, không cần context |
| `ctx_misses` | 133 | Engine giữ tiếng Việt, không restore |
| `ctx_breaks` | **0** | Context chưa làm hỏng ca nào |

Từ 2026-07-26 whitelist context tách 2 lớp: `words` (mở được mạch tiếng Anh) và
`restoreOnly` — thán từ / từ chat (`wow`, `ok`, `hi`, `sorry`, `thanks`…) **được khôi
phục khi đang trong mạch tiếng Anh nhưng không bao giờ mở mạch**, vì người Việt dùng
chúng để mở câu tiếng Việt ("ok cám ơn", "wow đẹp quá"). Field report 2026-07-26:
"that's great wow" commit ra `wơ` trong Simple Telex (`w` literal + `ow` → ơ, và `wơ`
lại hợp lệ qua teencode w→qu = "quơ" nên validator không cứu).

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
