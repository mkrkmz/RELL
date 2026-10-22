# Ask AI's "Copy answer" uses the icon button style

Written against: 4f36db8 (main; `DESIGN.md` present but not yet committed)

## Evidence chain

- Surface: the Inspector, Ask AI section, after an answer has arrived (the latest exchange, and earlier ones shown under "N earlier questions").
- Problem: **Copy answer** is a `.plain` button — a small tertiary glyph with no hover or press wash — while **Copy result** in the same Inspector's result header is a DS icon button with the shared wash.
- Design evidence:
  - `Reader for Language Learner/Reader for Language Learner/UI/DSButtonStyles.swift`, file header: one hover rule for the whole button family ("a light wash under the pointer, a little more while pressed").
  - `docs/archive/ROADMAP-v18.md`, Sprint 1: `.plain` kept only for list rows, cards and the "clear" control inside a text field ("kalanlar liste satiri, kart, metin alani ici 'temizle'"); result buttons moved to the icon style ("sonuc dugmeleri (cam → ikon)").
  - Exemplar in the same surface: `App/InspectorView+ResultPanel.swift`, `resultToolbarButton(systemImage:label:tint:action:)` — `Label` + `DSIconButtonStyle(tint:)`, default tint `DS.Color.accent`, used for Copy result.
- Owner: `Reader for Language Learner/Reader for Language Learner/App/InspectorView+AskAI.swift`, the exchange row's copy button (the `HStack { Spacer(); Button { copyToClipboard(exchange.answer, …) } … }`).
- Scope and affected surfaces: every Ask AI exchange in the Inspector.
- Uncertainty: none for the style. The submit and stop buttons in the Ask AI input row are inside the text field's row and stay `.plain` (v18 S1 exception).

## Design decision

Copying an answer looks and responds the same in the Ask AI section as in the result header: an icon button from the DS family, in the accent, with the shared hover wash.

## Reuse

- `.buttonStyle(.dsIcon)` (`DSIconButtonStyle()` with `DS.Color.accent`), with `Label("Copy answer", systemImage: "doc.on.doc")`.
- Exemplar: `App/InspectorView+ResultPanel.swift` `resultToolbarButton` (Copy result).

No new primitive.

## Changes

1. `App/InspectorView+AskAI.swift`, the exchange's copy button
   - Change: replace the label `Image(systemName: "doc.on.doc").font(DS.Typography.icon(9)).foregroundStyle(DS.Color.textTertiary)` with `Label("Copy answer", systemImage: "doc.on.doc")`, and `.buttonStyle(.plain)` with `.buttonStyle(.dsIcon)`.
   - Preserve: the action (`copyToClipboard(exchange.answer, showFeedback: true)`), the trailing position, `.help("Copy answer")`, `.accessibilityLabel("Copy answer")`, and the condition `!exchange.answer.isEmpty`.
   - Verify: the copy button shows the accent glyph at the icon style's size and a wash under the pointer, like Copy result.

## Scope

- Inherit: every Ask AI exchange (latest and earlier).
- Verify: the exchange card's height and wrapping with a long answer; the narrowest Inspector width (`DS.Layout.inspectorMin`).
- Exclude: the Ask AI input row's submit and stop buttons; the "N earlier questions" chip (`.dsChip`).

## Validation

- Product: select a word, ask a follow-up in Ask AI, then copy the answer; the toast confirms the copy.
- Interface: light and dark appearance; Inspector following a dark page theme (Settings ▸ Appearance ▸ Inspector follows the page theme).
- System: no `.plain` icon button remains in the Ask AI exchange rows.
- Repository: `make ci-test` (only while the user's RELL is closed — guard with `pgrep -f "(Reader for Language Learner|RELL)\.app/Contents/MacOS"`) → all tests pass, including `AccessibilityAuditTests` (icon-only buttons keep a label).

## Stop conditions

- Stop if the result header's copy button no longer uses `DSIconButtonStyle`, or the Ask AI exchange row has been redesigned since this plan was written.

## Design documentation

- After acceptance and validation: none.
