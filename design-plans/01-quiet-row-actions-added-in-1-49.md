# Row actions added in 1.49 are quiet buttons

Written against: 4f36db8 (main; `DESIGN.md` present but not yet committed)

Reconciled 2026-10-21: first written for the repeat-aloud result row (reading-screen audit); the Inspector / study room / notebook audit found the same root problem in two more owners, so they join this plan instead of becoming separate ones.

## Evidence chain

- Surfaces:
  - the reader window's bottom lane while a selected sentence is repeated aloud, after a result is shown;
  - the study room's "Write a Sentence" card, and the same card opened from a word's page;
  - the Word Notebook: a word's page (hero row) and a saved sentence's page ("Saying it aloud" section).
- Problem: actions that sit in a row beside other actions are drawn as the system's bordered push buttons:
  - repeat aloud result row — **Listen**, **Slower** (beside a prominent **Say It Again**);
  - writing card — **Write Again**, **Save Sentence** (beside a prominent **Next** / **Done**) and **Skip** (beside a prominent **Check**);
  - word page — **Write a Sentence**; sentence page — **Say It Aloud**, while **Translate**, **+ Save** and **Fill Missing** on the same pages are already `.dsQuiet`.
- Design evidence:
  - `Reader for Language Learner/Reader for Language Learner/UI/DSButtonStyles.swift`, file header: "A screen has at most one primary button, for the step that moves on … actions in a row — Save, Listen, Anki — are quiet."
  - `docs/archive/ROADMAP-v18.md`, Sprint 1 approval (2026-10-15): "ekranda en fazla bir ana buton, yalniz ilerleten iste (satir ici Kaydet/Dinle/Anki sakin)"; Sprint 5: "Eksikleri Doldur sade dugme".
  - `DESIGN.md` ▸ Components ▸ Buttons: "actions in a row (Save, Listen, Anki) are quiet."
- Owners:
  - `Reader for Language Learner/Reader for Language Learner/UI/SpokenRepetitionView.swift`, `resultView(_:)`;
  - `Reader for Language Learner/Reader for Language Learner/UI/SentenceWritingCard.swift`, `buttons`;
  - `Reader for Language Learner/Reader for Language Learner/UI/SavedWordDetailSheet.swift`, `hero` (Write a Sentence) and `spokenRepetitionSection` (Say It Aloud).
- Scope and affected surfaces:
  - `SpokenRepetitionView` renders in `App/ContentView+Repeat.swift` (reader bottom lane), `UI/QuizView+Sentence.swift` (study-room sentence card), `UI/SavedWordDetailSheet.swift` (sentence page);
  - `SentenceWritingCard` renders in `UI/QuizView+Room.swift` (study room, "Write a Sentence" mode) and in a sheet from `UI/SavedWordDetailSheet.swift`;
  - `SavedWordDetailSheet` renders as the Word Notebook's page (`UI/WordNotebookView.swift`, `isPane: true`) and as a sheet from `UI/SavedWordsListView.swift`.
- Uncertainty: none. None of the listed buttons sets a `buttonStyle`, so macOS draws its default bordered push button at the row's control size.

## Design decision

Each row keeps one primary action — the step that moves on — and every other action in the row takes the app's quiet style: no fill, the icon in the accent, the label in the text colour, the shared hover and press wash.

## Reuse

- `DSQuietButtonStyle` via `.buttonStyle(.dsQuiet)` (`UI/DSButtonStyles.swift`), with each button's existing title or `Label(_:systemImage:)`.
- Exemplars: `UI/SelectionActionBar.swift` (Save and Analyze, `Label` + `.dsQuiet`); `UI/SavedWordDetailSheet.swift` — the **Translate** and **+ Save** buttons in `sentenceSections` / `sentenceWordsSection` and **Fill Missing**, all `.dsQuiet` on the same page.

No new primitive.

## Changes

1. `UI/SpokenRepetitionView.swift`, `resultView(_:)`
   - Change: add `.buttonStyle(.dsQuiet)` to **Listen** and to **Slower** (keep Slower's `.help`).
   - Preserve: **Say It Again** stays `.borderedProminent`; the close button stays `.dsIcon`; row order, score pill and the word-by-word result are unchanged.
   - Verify: Listen and Slower show no border or fill at rest, an accent icon and a text-colour label, a light wash under the pointer.
2. `UI/SentenceWritingCard.swift`, `buttons`
   - Change: add `.buttonStyle(.dsQuiet)` to **Write Again**, to the **Save Sentence** / **Saved** button and to **Skip**.
   - Preserve: **Next**, **Done** and **Check** stay `.borderedProminent` with their keyboard shortcuts; `.disabled(saved)` and every `.help` stay; the row's `.controlSize(.large)` stays (it still sizes the prominent buttons).
   - Verify: after a check, the row shows Write Again and Save Sentence quiet and Next prominent; before a check in the study room, Skip quiet and Check prominent.
3. `UI/SavedWordDetailSheet.swift`, `hero`
   - Change: give **Write a Sentence** `.buttonStyle(.dsQuiet)`; remove its `.controlSize(.small)` (the quiet style sets its own size).
   - Preserve: its position after the IPA, `Spacer`, `.help`, and the sheet it opens.
   - Verify: the button matches **Fill Missing** on the same page.
4. `UI/SavedWordDetailSheet.swift`, `spokenRepetitionSection`
   - Change: give **Say It Aloud** `.buttonStyle(.dsQuiet)`; remove its `.controlSize(.small)`.
   - Preserve: the condition `SpokenRepetitionRecognizer.isOffered(for:)`, the last-result line and `.help`.
   - Verify: the button matches **Translate** in the section above.

## Scope

- Inherit: the reader's bottom lane, the study room (sentence card and Write a Sentence), the Word Notebook's word and sentence pages, the sheet versions of the word page and the writing card.
- Verify: the writing card's row fits on one line in the study room card (`QuizView.roomCardWidth`, 680 pt) and in its 560 pt sheet; the result row of repeat aloud fits the study-room card; the notebook page at the window's minimum width.
- Exclude: the explainer's **Not Now / Continue**, **Stop**, **Try Again**, **Open System Settings** in `SpokenRepetitionView` (single steps); the word page sheet's own **Cancel / Save / Delete…** footer (a sheet's confirmation buttons).

## Validation

- Product: repeat a selected sentence (⌃⌘R) and use Listen / Slower; write a sentence in the study room (Write a Sentence), check it, save it, go Next, then Skip on the next card; open a word's page and a sentence's page in the notebook.
- Interface: page themes Original, Sepia and Night for the reader lane; light and dark appearance for the study room and notebook; Reduce Motion on (no hover animation).
- System: each row has at most one prominent button; no new button style or local styling.
- Repository: `make ci-test` (only while the user's RELL is closed — guard with `pgrep -f "(Reader for Language Learner|RELL)\.app/Contents/MacOS"`) → all tests pass, including `DesignSystemAuditTests`.

## Stop conditions

- Stop if `.dsQuiet` no longer exists in `UI/DSButtonStyles.swift`, or if any of the four rows has gained another prominent button since this plan was written.

## Design documentation

- After acceptance and validation: none — `DESIGN.md` already states the rule.
