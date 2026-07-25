import XCTest
@testable import TelexCore

// Context-based decision (engine.contextualEnglish, EXPERIMENTAL). After an English
// word, an AMBIGUOUS next word — composition is a valid Vietnamese syllable but the raw
// keys spell an English word — is restored to English. After a Vietnamese/undetermined
// word it stays Vietnamese. "he is" → "he is"; "sao í" (keys "sao is") → "sao í".

/// Type a space-separated sentence, committing each word at its boundary (like the
/// controller does), and return the committed words rejoined with spaces.
private func sentence(_ s: String, context: Bool) -> String {
    var e = TelexEngine()
    e.liveSpellCheck = true          // shipped default; needed for clean disambiguation
    e.contextualEnglish = context
    var words: [String] = []
    var wroteCurrent = false
    for ch in s {
        if ch == " " {
            words.append(e.commitText(autoRestore: true)); wroteCurrent = false
        } else {
            _ = e.feed(ch); wroteCurrent = true
        }
    }
    if wroteCurrent || words.isEmpty { words.append(e.commitText(autoRestore: true)) }
    return words.joined(separator: " ")
}

final class ContextEnglishTests: XCTestCase {

    // MARK: The examples from the spec

    func testEnglishRunPrefersEnglish() {
        // "is" alone composes "í"; after an English word it must stay "is".
        XCTAssertEqual(sentence("he is", context: true), "he is")
        XCTAssertEqual(sentence("she is", context: true), "she is")
        XCTAssertEqual(sentence("it is", context: true), "it is")
    }

    // Case is preserved and does not affect English detection (raw is lowercased for
    // the dictionary lookup): "He is" → "He is", "HE IS" → "HE IS".
    func testUppercaseEnglishRun() {
        XCTAssertEqual(sentence("He is", context: true), "He is")
        XCTAssertEqual(sentence("She is", context: true), "She is")
        XCTAssertEqual(sentence("It is", context: true), "It is")
        XCTAssertEqual(sentence("HE IS", context: true), "HE IS")
        XCTAssertEqual(sentence("He Is", context: true), "He Is")
        // Capitalised Vietnamese word → the next ambiguous word stays Vietnamese.
        XCTAssertEqual(sentence("Sao is", context: true), "Sao í")
        // Off: unchanged (composes the Vietnamese "Í").
        XCTAssertEqual(sentence("He is", context: false), "He í")
    }

    func testVietnameseOrUnknownKeepsVietnamese() {
        // After a valid Vietnamese word, the ambiguous word stays Vietnamese.
        XCTAssertEqual(sentence("sao is", context: true), "sao í")
        // A Vietnamese word BREAKS the English run (context = immediate previous word).
        XCTAssertEqual(sentence("he sao is", context: true), "he sao í")
    }

    // MARK: The gate — OFF must not change anything

    func testOffLeavesTelexUnchanged() {
        // With the feature off, "is" stays the Vietnamese "í" even after English.
        XCTAssertEqual(sentence("he is", context: false), "he í")
        XCTAssertEqual(sentence("she is", context: false), "she í")
        XCTAssertEqual(sentence("sao is", context: false), "sao í")
        // On or off, a genuinely Vietnamese sentence is identical.
        XCTAssertEqual(sentence("toi yeu em", context: true),
                       sentence("toi yeu em", context: false))
    }

    // MARK: previousWordEnglish classification + resetContext

    func testPreviousWordClassification() {
        var e = TelexEngine(); e.liveSpellCheck = true; e.contextualEnglish = true
        for ch in "he" { _ = e.feed(ch) }
        _ = e.commitText(autoRestore: true)
        XCTAssertTrue(e.previousWordEnglish, "\"he\" should seed English context")
        for ch in "sao" { _ = e.feed(ch) }
        _ = e.commitText(autoRestore: true)
        XCTAssertFalse(e.previousWordEnglish, "\"sao\" is Vietnamese → context cleared")
        // "she" is not a valid VN syllable → English by structure alone.
        for ch in "she" { _ = e.feed(ch) }
        _ = e.commitText(autoRestore: true)
        XCTAssertTrue(e.previousWordEnglish)
        // resetContext wipes it (focus / app switch).
        e.resetContext()
        XCTAssertFalse(e.previousWordEnglish)
    }

    // No preceding word (fresh field, or after a newline/new prompt which the controller
    // signals via resetContext) → the ambiguous word stays Vietnamese.
    func testNoPreviousWordKeepsVietnamese() {
        XCTAssertEqual(sentence("is", context: true), "í")          // very first word
        // English word, then a newline (resetContext), then "is" → "í" on the new line.
        var e = TelexEngine(); e.liveSpellCheck = true; e.contextualEnglish = true
        for ch in "he" { _ = e.feed(ch) }; _ = e.commitText(autoRestore: true)
        e.resetContext()                                            // newline / new prompt
        for ch in "is" { _ = e.feed(ch) }
        XCTAssertEqual(e.commitText(autoRestore: true), "í")
    }

    // Context does not leak across a resetContext(): "he" then reset then "is" → "í".
    func testResetContextBreaksTheRun() {
        var e = TelexEngine(); e.liveSpellCheck = true; e.contextualEnglish = true
        for ch in "he" { _ = e.feed(ch) }
        _ = e.commitText(autoRestore: true)
        e.resetContext()
        for ch in "is" { _ = e.feed(ch) }
        XCTAssertEqual(e.commitText(autoRestore: true), "í")
    }

    // In-word backspace must NOT clear the context — the PREVIOUS word is unchanged, so a
    // fixed-up ambiguous word still resolves against it. (The controller resets context
    // only on an EMPTY-buffer backspace, i.e. deleting back into committed text.)
    func testInWordBackspaceKeepsContext() {
        var e = TelexEngine(); e.liveSpellCheck = true; e.contextualEnglish = true
        for ch in "he" { _ = e.feed(ch) }; _ = e.commitText(autoRestore: true)   // prev = English
        _ = e.feed("i"); _ = e.backspace()          // in-word edit of the next word
        XCTAssertTrue(e.previousWordEnglish, "in-word backspace must not clear context")
        for ch in "is" { _ = e.feed(ch) }
        XCTAssertEqual(e.commitText(autoRestore: true), "is")   // still after "he" → English
    }

    // Hand-vetted ambiguous words: English inside an English run, Vietnamese otherwise.
    func testHandVettedContextWords() {
        let pairs = [("runs", "rún"), ("songs", "sóng"), ("sons", "són"),
                     ("moms", "móm"), ("cams", "cám"), ("lens", "lén"), ("rays", "ráy"),
                     ("vans", "ván"), ("bans", "bán"), ("tins", "tín"), ("tans", "tán"),
                     ("dams", "dám"), ("hams", "hám"), ("thus", "thú")]
        for (en, vn) in pairs {
            XCTAssertEqual(sentence(en, context: true), vn, "\(en) with no English before → \(vn)")
            XCTAssertEqual(sentence("she \(en)", context: true), "she \(en)", "she \(en) → English")
        }
        // "loans" is already an unconditional English-collision word → always English.
        XCTAssertEqual(sentence("loans", context: true), "loans")
        XCTAssertEqual(sentence("she loans", context: true), "she loans")
    }

    func testSpecPhrases() {
        XCTAssertEqual(sentence("she thus", context: true), "she thus")
        XCTAssertEqual(sentence("their moms", context: true), "their moms")
        // …and each stays Vietnamese with the feature OFF.
        XCTAssertEqual(sentence("she thus", context: false), "she thú")
        XCTAssertEqual(sentence("their moms", context: false), "their móm")
    }

    // Clearly-Vietnamese words are NEVER flipped, even mid English run (no ambiguity).
    func testUnambiguousVietnameseNeverFlips() {
        // "he được" — "được" has no English spelling, stays Vietnamese after English.
        XCTAssertEqual(sentence("he dduowcj", context: true), "he được")
        // "he tieengs" → "he tiếng" (valid VN, not an English word → not flipped).
        XCTAssertEqual(sentence("he tieengs", context: true), "he tiếng")
    }
}
