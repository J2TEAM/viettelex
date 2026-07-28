// InPlaceProbe.swift
// Pure decision logic for the input controller's "does this app honor
// insertText replacementRange?" probe. Kept here (not in the App target) so it is
// unit-testable without IMKit: the controller feeds it the client's post-edit caret
// and read-back; tests feed it values from simulated clients.
//
// Background: the controller edits text in place with
//   client.insertText(insert, replacementRange: NSRange(location: start, length: bs))
// A compliant app REPLACES the `bs` chars at `start` with `insert`. Some apps
// (Terminal, iTerm2's CJK IMKit path, Mac Catalyst like WhatsApp, Electron/CEF like
// Lark) ignore the range and APPEND `insert` at the caret instead — tone edits then
// pile up without replacing, so diacritics never render.
//
// Detection history — read-back of the inserted TEXT proved unreliable twice:
//   • Old probe read the text BEFORE the caret; that holds `insert` in BOTH cases
//     (compliant: replaced there; append: freshly appended) → false-positive.
//   • Reading the TARGET region [start, start+len) fixes the honest case, but apps
//     that ECHO their read-back (iTerm2, Lark) still return `insert` there → still
//     false-positive.
// The robust signal is the post-edit CARET position, which every IME-aware app must
// report faithfully to place its candidate window. A compliant replace leaves the
// caret at `start + len`; an ignored-range append leaves it `bs` further right, at
// `start + bs + len`. Text read-back is kept only as a fallback when the caret is
// unavailable, and an inconclusive probe never condemns a (probably working) app.

public enum InPlaceProbe {

    public enum Verdict {
        case honored        // caret CONFIRMS the replace → keep the (underline-free) in-place path
        case appended       // the edit demonstrably did NOT replace → marked text (underline, always renders)
        case inconclusive   // the app's self-report is IMPOSSIBLE (see `verdict`) → learn nothing, re-probe
    }

    /// How far BEHIND the expected post-replace caret a report may land and still be read
    /// as a stale/foreign-coordinate answer rather than evidence (see `verdict`).
    static let maxCaretLag = 4

    /// Whether this edit is a usable probe. Only a REAL replace (bs > 0) with no
    /// pending selection (clear == 0) discriminates: a pure insert (bs == 0) lands
    /// identically whether or not the app honors the range, so confirming "in-place
    /// good" on one is exactly the false-positive that locked broken apps in place.
    /// `needsProbe` is the caller's "not yet classified" flag.
    public static func shouldProbe(insertLength: Int, bs: Int, clear: Int, needsProbe: Bool) -> Bool {
        insertLength > 0 && bs > 0 && clear == 0 && needsProbe
    }

    /// Classify a probed replace of `bs` chars at `start` with `insertLength` chars.
    ///
    /// - `caret`: the client's caret location AFTER the edit (`nil` if it reports
    ///   none). This is the primary, hardest-to-fake signal.
    /// - `regionReadback`: text the client returns for `[start, start+insertLength)`
    ///   (`nil` if unavailable). Fallback only — some apps echo it, so it can never
    ///   OVERRIDE a caret that says "appended".
    /// - `inserted`: the string we asked the client to place.
    ///
    /// Safety-first: keep the underline-free in-place path ONLY when there is
    /// positive proof the replace happened — the caret landed exactly at `start+len`.
    /// Everything else (caret at the append position, caret elsewhere, or no caret
    /// with a read-back that doesn't match) returns `.appended` → marked text, which
    /// ALWAYS renders Vietnamese (just with an underline). This is the right default:
    /// a wrong in-place guess silently drops diacritics, whereas marked text only
    /// costs a cosmetic underline — so when unsure, prefer the mode that always works.
    public static func verdict(axRegion: String?, caret: Int?, start: Int, bs: Int,
                               insertLength: Int, regionReadback: String?, inserted: String) -> Verdict {
        // GROUND TRUTH FIRST: the Accessibility tree reports the field's real content,
        // independent of the app's IMKit self-report (caret / attributedSubstring),
        // which Lark fakes. When an AX read is available it decides outright — the
        // engine strips the common prefix, so axRegion == inserted iff the replace
        // actually landed at `start`.
        if let ax = axRegion { return ax == inserted ? .honored : .appended }

        let expectedReplace = start + insertLength
        let regionDisagrees = regionReadback.map { $0 != inserted } ?? false
        if let c = caret {
            // The caret sits exactly where a compliant replace leaves it — the strongest
            // self-report there is (an app needs a truthful caret to place its own candidate
            // window). If the region read-back disagrees at the same time, the app is
            // contradicting ITSELF: Chromium serves `attributedSubstring` from a cache that
            // is stale right after `insertText`, so a mismatch there while the caret is
            // honest means "read-back is lagging", not "the replace failed" — the deferred
            // Accessibility read confirmed the replace HAD landed in exactly this state
            // (Google Sheets, issue #31, and Jira before it). Learn nothing and let the AX
            // ground truth settle it, instead of demoting a healthy field mid-word.
            //
            // Lark, the reason the region read-back was ever allowed to override a caret, is
            // still covered: it answers a CONSTANT caret (1), which equals `expectedReplace`
            // at one coincidental offset only, and `HonorTracker` refuses to commit to
            // in-place until two honored verdicts land at DIFFERENT offsets.
            if c == expectedReplace { return regionDisagrees ? .inconclusive : .honored }
            // Region says our text is not there AND the caret does not describe a replace:
            // two independent signals agree it failed.
            if regionDisagrees { return .appended }
            // A caret BEHIND the replace position is not evidence of anything. Follow the
            // arithmetic: a replace leaves the caret at `expectedReplace`, an append leaves
            // it FURTHER RIGHT at start+bs+insertLength. So a report to the LEFT of
            // `expectedReplace` cannot describe either outcome — it is a stale answer (the
            // app reports the caret from before our edit) or a foreign coordinate space
            // (ProseMirror counts document positions, not characters).
            //
            // Measured from `expectedReplace`, not from `start`: both real-world lies live
            // in that gap. Tester logs 2026-07-27 — Jira in Chrome reported caret=1338 for
            // expectedReplace=1340, and Google Sheets reported caret=2 for
            // expectedReplace=3 (one edit behind) while the Accessibility tree confirmed
            // BOTH replaces had landed. Reading those as "appended" demoted healthy fields
            // to marked text: Jira flashed a selection and mangled text, and a Sheets cell
            // that is selected-but-not-editing ignores marked text entirely, so typing did
            // nothing until the user double-clicked the cell (issue #31).
            //
            // The window stays NARROW so real evidence still wins: a stale report is off by
            // an edit or a few node boundaries, while a CONSTANT garbage caret is not —
            // Lark answers 1 forever, so mid-field (expectedReplace=30) it stays
            // `.appended` and still demotes on the usual two strikes. Being unsure must not
            // cost more than a couple of probes (the caller bounds them).
            let behind = expectedReplace - c
            return behind > 0 && behind <= maxCaretLag ? .inconclusive : .appended
        }
        // No caret at all: a positive read-back match keeps in-place, a mismatch is the
        // only evidence we have (so trust it), and nothing at all → safe marked-text mode.
        if regionDisagrees { return .appended }
        return regionReadback != nil ? .honored : .appended
    }

    /// Confirmation tracker for SELF-REPORTED honored verdicts (caret / read-back —
    /// not an AX-backed read, which is ground truth and confirms on its own).
    ///
    /// Why: Lark returns a CONSTANT garbage caret (always 1, measured 2026-07-21 —
    /// see the deferred-reprobe experiment log). A single-probe rule locked it to the
    /// broken in-place path whenever the first tone edit happened to land where
    /// `start + insertLength` coincided with the garbage value (typing at the start
    /// of an empty message field: expReplace = 1). No fixed threshold can rule that
    /// class out — but a constant caret cannot equal `start + insertLength` at TWO
    /// DIFFERENT offsets, while a truthful caret always does. So: an app is only
    /// committed to the (silent-failure-prone) in-place path after honored verdicts
    /// at two distinct expected-caret positions.
    public struct HonorTracker {
        private var firstExpReplace: Int?

        public init() {}

        /// Record an honored probe whose expected post-replace caret was
        /// `expReplace`. Returns true when in-place is CONFIRMED — i.e. this is the
        /// second honored verdict at a *different* offset than the first. A repeat
        /// at the same offset carries no new information and keeps waiting.
        public mutating func recordHonored(expReplace: Int) -> Bool {
            if let first = firstExpReplace, first != expReplace { return true }
            firstExpReplace = expReplace
            return false
        }
    }
}
