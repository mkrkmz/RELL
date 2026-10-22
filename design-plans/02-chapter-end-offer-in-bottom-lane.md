# The end-of-chapter check offer sits in the bottom lane, not over the text

Written against: 4f36db8 (main; `DESIGN.md` present but not yet committed)

## Evidence chain

- Surface: an EPUB in the reader window, scrolled to the end of a chapter of at least 400 words, with "Comprehension Check at Chapter End" on (Settings ▸ Study ▸ Reading Loop).
- Problem: the offer card ("Chapter N finished · Check what you understood…", Not Now, Start) is laid over the bottom of the page and covers the last lines of the text.
- Design evidence:
  - `docs/archive/ROADMAP-v18.md`, Sprint 4 approval (2026-10-15): everything over the text is on one opaque surface in three places — top strip, beside the text, bottom lane — and "alt serit sayfayi kisaltir, metnin ustune binmez" (the bottom lane shortens the page and does not cover the text).
  - `Reader for Language Learner/Reader for Language Learner/App/ContentView.swift`, comment above the bottom lane in `pdfColumn`: "The page gives them its height rather than being covered by them."
  - `DESIGN.md` ▸ Layout: "The bottom lane … shortens the page rather than covering it."
- Owner: `App/ContentView.swift` (`pdfColumn`) places it; `App/ContentView+Comprehension.swift` (`comprehensionOfferCard`) draws it.
- Scope and affected surfaces: the EPUB reading column only (the offer is never made for PDFs).
- Uncertainty: `pdfColumn` keeps the top "Previously in…" card as an overlay because a card appearing inside the stack above the web view once looped AppKit's layout (comment above `.overlay(alignment: .top)`). The bottom lane is in the same stack below the page and its items (the sentence translation strip, repeating aloud, the speech bar) appear and disappear there without that failure, so the lane is the established place — but the change must be checked with the window at its minimum size.

## Design decision

The offer is a bottom-lane item like the sentence translation strip: it takes its height from the page instead of covering it. It keeps its look — the opaque page-themed `dsReadingOverlay` card, the same copy and buttons, the same once-per-chapter rule.

## Reuse

- Bottom lane in `pdfColumn` (`App/ContentView.swift`): the `if … SentenceTranslationStrip(…)`, `repeatLane` and `SpeechPlaybackBar` items that follow the page in the same `VStack`.
- Exemplar: `App/ContentView+Repeat.swift` `repeatLane` — a `@ViewBuilder` computed view, drawn only when its model state is set and `!chromeHidden`, with `.dsReadingOverlay(…)`, a `maxWidth`, side padding and `.transition(.opacity.combined(with: .move(edge: .bottom)))`, animated from the column with `.animation(DS.Animation.standard, value: …)`.

No new primitive.

## Changes

1. `Reader for Language Learner/Reader for Language Learner/App/ContentView.swift`, `pdfColumn`
   - Change: remove `.overlay(alignment: .bottom) { comprehensionOfferCard }` and the `.animation(DS.Animation.standard, value: model.comprehensionOffer)` that follows it from the page `Group`. Insert `comprehensionOfferCard` as the first bottom-lane item, directly after the page and before the sentence translation strip. Add `.animation(DS.Animation.standard, value: model.comprehensionOffer)` next to the column's existing `.animation(…, value: translatableSentence)` and `.animation(…, value: model.repeatSentence)`.
   - Preserve: the top `.overlay(alignment: .top) { readingRecapCard }` stays an overlay; the order translation strip → repeating aloud → speech bar is unchanged.
   - Verify: at a chapter's end the card appears under the page and the page becomes shorter; no line of text is hidden behind it.
2. `Reader for Language Learner/Reader for Language Learner/App/ContentView+Comprehension.swift`, `comprehensionOfferCard`
   - Change: replace the trailing `.padding(DS.Spacing.md)` with `.padding(.horizontal, DS.Spacing.md)` and `.padding(.bottom, DS.Spacing.sm)`, as `repeatLane` does, so the card sits in the lane's rhythm instead of floating with padding on every side.
   - Preserve: `.dsReadingOverlay(RoundedRectangle(cornerRadius: DS.Radius.md))`, `.frame(maxWidth: 520)`, the transition, the copy, both buttons and their actions, the `!chromeHidden` condition.
   - Verify: the card is horizontally centred in the column with the same side gutter as the other lane items.

## Scope

- Inherit: the EPUB reading column at a chapter's end.
- Verify: the card together with the sentence translation strip (select a sentence on the last screen of a chapter); together with repeating aloud; Zen mode (`chromeHidden`, the card must not show); the window at its minimum size (`DS.Layout.windowMin`).
- Exclude: the "Previously in…" card (deliberately an overlay at the top), the chapter panel's "Check What You Understood" row, PDF documents.

## Validation

- Product: open an EPUB, scroll to the end of a long chapter; the offer appears; Not Now hides it for that chapter, Start opens the check sheet.
- Interface: Original, Sepia and Night page themes; a narrow window; the reading position stays where it was when the card appears and when it goes (the page shortens by the card's height, as it does for the translation strip).
- System: no new overlay over the text; the lane has the same item pattern throughout.
- Repository: `make ci-test` (only while the user's RELL is closed — guard with `pgrep -f "(Reader for Language Learner|RELL)\.app/Contents/MacOS"`) → all tests pass, including `WindowLayoutTests` (shrinks the real window to catch layout loops).

## Stop conditions

- Stop if showing the card in the lane loops AppKit's layout (a crash or hang with "more Update Constraints passes than views", or `WindowLayoutTests` failing); report it instead of returning the card to an overlay over the text.
- Stop if the bottom lane's structure in `pdfColumn` has changed since this plan was written.

## Design documentation

- After acceptance and validation: none — `DESIGN.md` ▸ Layout already states the rule.
