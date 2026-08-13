#!/usr/bin/env swift
// stress-typing.swift — bơm keystroke tốc độ phi nhân loại (mặc định 500 phím/s)
// để bắt race/corruption trong đường xử lý phím (checklist.md mục 11.8).
//
// Đây là bài test ĐÚNG ĐẮN (correctness), không phải đo tốc độ: các bộ gõ từng
// dính bug chỉ lộ ra khi gõ nhanh (hỏng số liệu, mất dòng đầu, đảo thứ tự dấu).
//
// Usage:
//   swift Scripts/stress-typing.swift [keys_per_sec=500] [repeats=20]
//   swift Scripts/stress-typing.swift --corpus Scripts/terminal-regression-cases.json \
//       [--rate 7] [--repeats 10]
//   → focus vào ô text đích trong 3s countdown; script gõ câu Telex chuẩn
//     lặp lại, in ra văn bản KỲ VỌNG để so sánh mắt thường / diff.
//
// Requires: Accessibility cho terminal chạy script (để post CGEvent).

import Cocoa

let args = CommandLine.arguments

struct TerminalCase: Codable {
    let name: String
    let keys: String
    let expected: String
}

func value(after flag: String) -> String? {
    guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
    return args[index + 1]
}

let corpusPath = value(after: "--corpus")
let rate = value(after: "--rate").flatMap(Double.init)
    ?? (corpusPath == nil && args.count > 1 ? Double(args[1]) : nil)
    ?? 500
let repeats = value(after: "--repeats").flatMap(Int.init)
    ?? (corpusPath == nil && args.count > 2 ? Int(args[2]) : nil)
    ?? 20

guard rate > 0, repeats > 0 else {
    fputs("rate and repeats must be greater than zero\n", stderr)
    exit(2)
}

// Câu test chuẩn của checklist + kỳ vọng sau khi engine xử lý.
let telexKeys = "ddaay laf tieengs vieejt raats hay "
let expected  = "đây là tiếng việt rất hay "
let cases: [TerminalCase]
if let corpusPath {
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: corpusPath))
        cases = try JSONDecoder().decode([TerminalCase].self, from: data)
    } catch {
        fputs("cannot load corpus \(corpusPath): \(error)\n", stderr)
        exit(2)
    }
    guard !cases.isEmpty, cases.allSatisfy({ !$0.name.isEmpty && !$0.keys.isEmpty }) else {
        fputs("corpus must contain named, non-empty cases\n", stderr)
        exit(2)
    }
} else {
    cases = [TerminalCase(name: "legacy-stress", keys: telexKeys, expected: expected)]
}

// US-layout virtual keycodes cho a-z + space.
let keycode: [Character: CGKeyCode] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8,
    "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
    "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45,
    "m": 46, " ": 49,
]

let src = CGEventSource(stateID: .hidSystemState)
func post(_ ch: Character) {
    guard let k = keycode[ch] else { return }
    CGEvent(keyboardEventSource: src, virtualKey: k, keyDown: true)?.post(tap: .cghidEventTap)
    CGEvent(keyboardEventSource: src, virtualKey: k, keyDown: false)?.post(tap: .cghidEventTap)
}

func postEnter() {
    let enter: CGKeyCode = 36
    CGEvent(keyboardEventSource: src, virtualKey: enter, keyDown: true)?.post(tap: .cghidEventTap)
    CGEvent(keyboardEventSource: src, virtualKey: enter, keyDown: false)?.post(tap: .cghidEventTap)
}

let gap = 1.0 / rate
let keysPerPass = cases.reduce(0) { $0 + $1.keys.count }
let boundaryKeys = corpusPath == nil ? 0 : cases.count
let totalKeys = (keysPerPass + boundaryKeys) * repeats
print("Sẽ gõ \(repeats) vòng × \(cases.count) ca @ \(rate) phím/s (\(totalKeys) phím).")
print("Focus vào ô text đích... 3s")
Thread.sleep(forTimeInterval: 3)

let t0 = DispatchTime.now().uptimeNanoseconds
for _ in 0..<repeats {
    for testCase in cases {
        for ch in testCase.keys {
            post(ch)
            Thread.sleep(forTimeInterval: gap)
        }
        if corpusPath != nil {
            postEnter()
            Thread.sleep(forTimeInterval: gap)
        }
    }
}
let secs = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000_000

print(String(format: "\nXong: %d phím trong %.1fs (%.0f phím/s thực tế).",
             totalKeys, secs, Double(totalKeys) / secs))
if corpusPath == nil {
    print("\nVăn bản KỲ VỌNG (lặp \(repeats) lần):")
    print(String(repeating: expected, count: repeats))
    print("\nSo với văn bản thực tế trong app: không được mất/lặp/sai dấu ký tự nào.")
} else {
    print("\nReader sẽ tự đối chiếu \(cases.count * repeats) dòng với corpus.")
}
