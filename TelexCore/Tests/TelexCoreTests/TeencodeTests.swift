import XCTest
@testable import TelexCore

// TEENCODE (feature 2026-08-04, maintainer-approved). Two rules, both about chat
// spellings that are NOT dictionary Vietnamese but ARE what the user meant:
//
//  (a) ELONGATION — the composition splits as `valid syllable` + a run of ONE repeated
//      letter, run ≥ 3 ("hôn"+"gggg", "có"+"aaaaaa", "ạ"+"aaaaaaa", "đẹp"+"ppppp").
//      Live spell-check must not FREEZE such a word (freezing folded the tone key back
//      to a literal and showed raw "cosaaaa"), the tone must stay inside the HEAD (free
//      marking otherwise drifts it onto the tail: "coáaaa"), and the boundary must KEEP
//      the composition instead of auto-restoring the raw keystrokes.
//  (b) the OPEN rime "ie" is a valid syllable (SyllableValidator), so "bies"→bíe,
//      "miej"→mịe commit as rendered with no special boundary rule at all.
//
// Everything runs with the shipped defaults for this feature: autoRestore + freeMarking
// + liveSpellCheck all ON.
final class TeencodeTests: XCTestCase {

    private func engine() -> TelexEngine {
        var e = TelexEngine()
        e.freeMarking = true
        e.liveSpellCheck = true
        return e
    }

    private func commit(_ keys: String) -> String {
        var e = engine()
        for ch in keys { _ = e.feed(ch) }
        return e.commitText(autoRestore: true)
    }

    /// Screen state after typing `keys` (what the user is looking at mid-word).
    private func screen(_ keys: String) -> String {
        var e = engine()
        for ch in keys { _ = e.feed(ch) }
        return e.composed
    }

    // MARK: - The nine field examples

    func testElongationCommits() {
        // Tail letter counts follow doubler-cancel semantics: a mark doubler eats one key
        // (aa→â) and the third key cancels it back to two literal letters, so 7 typed a's
        // land as 6 ("cosaaaaaaa"); a consonant tail has no doubler, so every key lands.
        XCTAssertEqual(commit("ajaaaaaaaaa"), "ạaaaaaaaa")
        XCTAssertEqual(commit("hoonggggg"), "hônggggg")
        XCTAssertEqual(commit("vaanggggg"), "vânggggg")
        XCTAssertEqual(commit("cosaaaaaaa"), "cóaaaaaa")
        XCTAssertEqual(commit("quafaaaa"), "quàaaa")
        XCTAssertEqual(commit("ddepjpppp"), "đẹppppp")
        // Already worked before the feature — must not regress (no transform at all).
        XCTAssertEqual(commit("xinnnn"), "xinnnn")
    }

    func testIeRimeCommits() {
        XCTAssertEqual(commit("bies"), "bíe")
        XCTAssertEqual(commit("miej"), "mịe")
        // Same class, other tones / onsets.
        XCTAssertEqual(commit("thies"), "thíe")
        XCTAssertEqual(commit("mief"), "mìe")
        // Toneless "ie" was already committed verbatim (nothing transforms) — pinned so
        // the new rime can't change it.
        XCTAssertEqual(commit("die"), "die")
        XCTAssertEqual(commit("tie"), "tie")
        XCTAssertEqual(commit("lie"), "lie")
        // Closed "ie" rimes stay OUT of the table: their real spelling is iê, so English
        // keeps restoring.
        XCTAssertEqual(commit("diet"), "diet")
        XCTAssertEqual(commit("field"), "field")
        XCTAssertEqual(commit("client"), "client")
        XCTAssertEqual(commit("science"), "science")
    }

    /// Rule (a) on top of rule (b): the elongation head may itself be an "ie" syllable.
    func testElongatedIeSyllable() {
        XCTAssertEqual(commit("bieseee"), "bíeee")
        XCTAssertEqual(commit("bieseeee"), "bíeeee")
    }

    // MARK: - The freeze must not fire, and must re-evaluate

    /// The word must be composed ON SCREEN while typing, not replayed as literal keys:
    /// the freeze used to fire at the first invalid point and fold the tone key back
    /// ("cosaaaa" on screen). One extra character is genuinely ambiguous, so the freeze
    /// still fires there; the run's third letter resolves it and the screen re-renders in
    /// ONE keystroke.
    func testFreezeReEvaluatesOnElongation() {
        XCTAssertEqual(screen("cos"), "có")
        XCTAssertEqual(screen("cosa"), "cóa")          // still a plausible prefix
        XCTAssertEqual(screen("cosaa"), "coấ")         // the aa doubler fired
        XCTAssertEqual(screen("cosaaa"), "cosaa")      // cancel + run of 2: could be a typo
        XCTAssertEqual(screen("cosaaaa"), "cóaaa")     // run of 3 ⇒ unfrozen, tone back
        XCTAssertEqual(screen("cosaaaaa"), "cóaaaa")
        // Same for a consonant tail with a pending tone (the j must never fold to 'j').
        XCTAssertEqual(screen("ddepjppp"), "đẹpppp")
        XCTAssertEqual(screen("ddepjpppp"), "đẹppppp")
        // And for the doubler-cancel path.
        XCTAssertEqual(screen("ajaaaa"), "ạaaa")
    }

    /// The tone belongs to the HEAD: free marking would otherwise drift it onto the
    /// first tail vowel ("coáaaa", "aạaaa").
    func testTonePlacementStaysInHead() {
        XCTAssertEqual(screen("cosaaaaaa"), "cóaaaaa")
        XCTAssertEqual(screen("ajaaaaaa"), "ạaaaaa")
        XCTAssertEqual(screen("quafaaaa"), "quàaaa")
    }

    /// ⌫ over an elongation tail must stay in sync: each backspace removes exactly one
    /// displayed character, and the freeze/tone state is recomputed for the shorter word
    /// (no retroactive re-marking, no desync with the screen).
    func testBackspaceOverElongationTail() {
        var e = engine()
        for ch in "cosaaaaa" { _ = e.feed(ch) }
        XCTAssertEqual(e.composed, "cóaaaa")
        // Each step is EXACTLY what forward typing shows at that length (see
        // testFreezeReEvaluatesOnElongation) — ⌫ replays the freeze, it never lifts it.
        let expected = ["cóaaa", "cosaa", "coấ", "co", "c", ""]
        for want in expected {
            _ = e.backspace()
            XCTAssertEqual(e.composed, want, "⌫ desync")
        }
    }

    /// commitBoundary (event-tap client) must agree with commitText (marked-text client)
    /// on every teencode word — a keep is `.none`, never a partial rewrite.
    func testBoundaryActionsAgree() {
        for keys in ["ajaaaaaaaaa", "hoonggggg", "vaanggggg", "cosaaaaaaa", "quafaaaa",
                     "bies", "miej", "xinnnn", "ddepjpppp", "bieseee"] {
            var e = engine()
            for ch in keys { _ = e.feed(ch) }
            let composedBefore = e.composed
            let peek = e.peekCommitText(autoRestore: true)
            let action = e.commitBoundary(autoRestore: true)
            XCTAssertEqual(peek, composedBefore, "\(keys): teencode must keep the screen")
            switch action {
            case .none: break
            default: XCTFail("\(keys): boundary must not rewrite a kept teencode word")
            }
        }
    }

    // MARK: - Guards: nothing else may change

    /// Auto-restore's flagship cases and the English protections must be untouched.
    func testEnglishGuards() {
        XCTAssertEqual(commit("retore"), "retore")
        XCTAssertEqual(commit("google"), "google")
        // "his" is a KNOWN pre-existing miss of the collision table (hí wins without
        // context; the English-context feature is what restores it) — pinned to prove
        // teencode changed nothing here.
        XCTAssertEqual(commit("his"), "hí")
        XCTAssertEqual(commit("excess"), "excess")
        XCTAssertEqual(commit("vibes"), "vibes")
        // Screen-truth trailing cancel (POLICY V2, 2026-07-31) — untouched.
        XCTAssertEqual(commit("pass"), "pas")
    }

    /// English DOUBLES letters, it never triples them — that is why the elongation run
    /// must be ≥ 3. These all restore (a run of 2 is not an elongation).
    func testDoubledEnglishStillRestores() {
        for w in ["wall", "walls", "watt", "watts", "will", "wifi",
                  "balls", "bills", "calls", "cells", "eggs", "apps", "inns", "ascii"] {
            XCTAssertEqual(commit(w), w, "\(w): a run of 2 must not read as elongation")
        }
    }

    /// KNOWN COST of the "ie" rime (maintainer decision 2026-08-04): these English words
    /// now compose to a valid syllable and are NOT in the generated collision table, so
    /// they commit as Vietnamese. Pinned deliberately — if the table is ever regenerated
    /// (`swift run gen-english`) these flip back to raw and this test is the reminder to
    /// update the suite floor with them.
    func testKnownCostOfIeRime() {
        XCTAssertEqual(commit("dies"), "díe")
        XCTAssertEqual(commit("ties"), "tíe")
        XCTAssertEqual(commit("lies"), "líe")
        XCTAssertEqual(commit("tries"), "tríe")
        XCTAssertEqual(commit("life"), "lìe")
        XCTAssertEqual(commit("chief"), "chìe")
        XCTAssertEqual(commit("rise"), "ríe")
        XCTAssertEqual(commit("tire"), "tỉe")
        XCTAssertEqual(commit("hire"), "hỉe")
        XCTAssertEqual(commit("mixer"), "mỉe")
    }

    /// Real Vietnamese must be unaffected by the tone-scope cap and the freeze escape.
    func testVietnameseUnaffected() {
        let pairs = [("tieengs", "tiếng"), ("nguwowif", "người"), ("dduowcj", "được"),
                     ("vieejt", "việt"), ("hoaf", "hòa"), ("thuyr", "thủy"),
                     ("xinnn", "xinnn"), ("khoong", "không"), ("ddepj", "đẹp"),
                     ("hoon", "hôn"), ("vaang", "vâng"), ("cos", "có")]
        for (keys, want) in pairs {
            XCTAssertEqual(commit(keys), want, keys)
        }
    }

    /// Mode-agnostic: VNI types the same teencode shapes with digit tone keys.
    func testVniTeencode() {
        func commitVNI(_ keys: String) -> String {
            var e = TelexEngine()
            e.vniMode = true
            e.freeMarking = true
            e.liveSpellCheck = true
            for ch in keys { _ = e.feed(ch) }
            return e.commitText(autoRestore: true)
        }
        XCTAssertEqual(commitVNI("bie1"), "bíe")        // sắc via VNI 1
        XCTAssertEqual(commitVNI("mie5"), "mịe")        // nặng via VNI 5
        // VNI has no letter doubler (marks are digits 6-9), so every typed a lands —
        // one more than the Telex spelling "cosaaaaaaa" produces.
        XCTAssertEqual(commitVNI("co1aaaaaaa"), "cóaaaaaaa")
        XCTAssertEqual(commitVNI("ho6nggggg"), "hônggggg")
        XCTAssertEqual(commitVNI("va6nggggg"), "vânggggg")
    }
}
