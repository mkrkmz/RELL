# The listening ring's offset uses spacing tokens

Written against: 4f36db8 (main; `DESIGN.md` present but not yet committed)

## Evidence chain

- Surface: the microphone circle while listening (repeat aloud) — the reader's bottom lane, a study-room sentence card, a saved sentence's page.
- Problem: the halo around the red microphone circle is pushed outward with a raw `.padding(-5)`.
- Design evidence:
  - `CLAUDE.md` ▸ Kodlama Kurallari: "Tasarim tokenleri icin HER ZAMAN `DS` namespace'ini kullan (DS.Colors, DS.Typography, DS.Spacing, DS.Radius)".
  - `Reader for Language Learner/Reader for Language Learner/UI/DesignSystem.swift`, `DS.Spacing.hairline`: "sums with the steps below keep exact sizes in tokens".
  - `DESIGN.md` ▸ Layout: "An exact size between steps is a sum of steps … never a new literal."
- Owner: `Reader for Language Learner/Reader for Language Learner/UI/SpokenRepetitionView.swift`, `circle(symbol:tint:ring:)`.
- Scope and affected surfaces: every `SpokenRepetitionView` (`App/ContentView+Repeat.swift`, `UI/QuizView+Sentence.swift`, `UI/SavedWordDetailSheet.swift`); the circle shows in the reading row (no halo) and the listening row (halo).
- Uncertainty: none. 5 = `DS.Spacing.xs` (4) + `DS.Spacing.hairline` (1). `DesignSystemAuditTests` does not catch it because its numeric-padding rule doesn't match a negative literal.

## Design decision

The halo's outward offset is written in spacing tokens, so the value is the same 5 pt and the line follows the design-system rule.

## Reuse

- `DS.Spacing.xs`, `DS.Spacing.hairline`.
- Exemplar: `App/ContentView+ReadingLoop.swift` `chapterPill` — `.padding(.vertical, DS.Spacing.xxs + DS.Spacing.hairline)`, a size between steps written as a sum.

No new primitive.

## Changes

1. `Reader for Language Learner/Reader for Language Learner/UI/SpokenRepetitionView.swift`, `circle(symbol:tint:ring:)`
   - Change: in `.overlay(Circle().strokeBorder(tint.opacity(ring ? 0.25 : 0), lineWidth: 5).padding(-5))`, replace `.padding(-5)` with `.padding(-(DS.Spacing.xs + DS.Spacing.hairline))`.
   - Preserve: the stroke width, the halo's opacity, the circle's size, colour and symbol.
   - Verify: the listening halo looks exactly as before (same 5 pt offset).

## Scope

- Inherit: the three surfaces above.
- Verify: the listening row in the reader's bottom lane.
- Exclude: the stroke's `lineWidth: 5` and the circle's `.frame(width: 30, height: 30)` — neither is spacing, and no token governs them.

## Validation

- Product: repeat a sentence aloud; while listening, the red microphone circle has the same soft halo.
- Interface: Original and Night page themes.
- System: no raw spacing literal remains in `circle(symbol:tint:ring:)`.
- Repository: `make ci-test` (only while the user's RELL is closed — guard with `pgrep -f "(Reader for Language Learner|RELL)\.app/Contents/MacOS"`) → all tests pass.

## Stop conditions

- Stop if `circle(symbol:tint:ring:)` no longer draws the halo with a padding offset.

## Design documentation

- After acceptance and validation: none.
