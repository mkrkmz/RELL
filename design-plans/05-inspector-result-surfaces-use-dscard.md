# The Inspector's result surfaces use the shared card chrome

Written against: 4f36db8 (main; `DESIGN.md` present but not yet committed)

## Evidence chain

- Surface: the Inspector's result area for a built-in module — the answer body, the loading view and the "Not asked yet." view.
- Problem: the three views each hand-build the same chrome — `.background(DS.Color.cardInset)` + `.clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))` — instead of the shared card modifier. No visual difference today; the chrome can drift apart from the system's one card definition.
- Design evidence:
  - `Reader for Language Learner/Reader for Language Learner/UI/DesignSystem.swift`, `View.dsCard(padding:surface:radius:stroke:shadow:)`: "The app's one card chrome: surface + rounded corner + hairline stroke (+ optional shadow). Covers the variants the hand-rolled sites had drifted into; genuinely bespoke chrome stays inline with a `// DS-exempt:` note." `DS.CardStroke.none` exists for chrome without a stroke.
  - `DesignSystem.swift`, `DS.Color.cardInset`: the surface scale's level for "sunken content (result body)".
  - `DESIGN.md` ▸ Components: "Cards use `dsCard()` … Hand-made card chrome needs a `// DS-exempt:` note."
- Owner: `Reader for Language Learner/Reader for Language Learner/App/InspectorView+ResultPanel.swift` — the answer body (the `ScrollView` branch ending in `.background(DS.Color.cardInset).clipShape(…lg)`), `loadingView`, `emptyOutputView(module:)`.
- Scope and affected surfaces: the Inspector's result panel for built-in modules.
- Uncertainty: none. `dsCard(padding: nil, …)` applies `.padding(.all, 0)`, then `.background(surface)`, then `.clipShape(RoundedRectangle(cornerRadius: radius))`, and draws no stroke with `.none` — the same result as today.

## Design decision

The three result views take their chrome from `dsCard` with the result body's documented surface and the panel radius, so the Inspector's result area is defined by the system's single card chrome.

## Reuse

- `.dsCard(padding: nil, surface: DS.Color.cardInset, radius: DS.Radius.lg, stroke: .none)`.
- Exemplar of a stroke-less `dsCard`: `App/DashboardActivityCard.swift` uses `dsCard(padding: nil, radius: DS.Radius.md, stroke: .hairline)` — same modifier, explicit arguments.

No new primitive.

## Changes

1. `App/InspectorView+ResultPanel.swift` — answer body, `loadingView`, `emptyOutputView(module:)`
   - Change: in each, replace `.background(DS.Color.cardInset)` followed by `.clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))` with `.dsCard(padding: nil, surface: DS.Color.cardInset, radius: DS.Radius.lg, stroke: .none)`.
   - Preserve: every modifier before and after the pair (`.textSelection`, `.frame(maxWidth: .infinity, maxHeight: .infinity)`, `.lineSpacing(4)`), content and order.
   - Verify: the three views look exactly as before in light and dark appearance.

## Scope

- Inherit: the Inspector's result panel.
- Verify: the custom-module result view in `App/InspectorView+Custom.swift` is untouched (it has its own header strip and is not part of this change).
- Exclude: the error view (`DS.Color.danger.opacity(0.06)` with `DS.Radius.sm` is a different, warning-like surface); the module icon tile in the result header (a small tinted badge, not a card).

## Validation

- Product: select a word with auto-run off: "Not asked yet." with Get; press Get: loading; the answer arrives.
- Interface: light and dark appearance; Inspector following the Night page theme.
- System: no other `.background(DS.Color.cardInset)` + `.clipShape` pair remains in the result panel.
- Repository: `make ci-test` (only while the user's RELL is closed — guard with `pgrep -f "(Reader for Language Learner|RELL)\.app/Contents/MacOS"`) → all tests pass, including `WindowLayoutTests` and the Inspector layout guards.

## Stop conditions

- Stop if `dsCard`'s modifier order or `DS.CardStroke.none` has changed so that the result would differ visually.

## Design documentation

- After acceptance and validation: none.
