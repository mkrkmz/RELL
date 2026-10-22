---
version: alpha
name: RELL
description: Design language of RELL, a macOS reader for language learners — PDF and EPUB reading with AI explanations of the selected word and spaced review of saved words.
colors:
  page-background: "#EBEBEB"
  reading-overlay: "#FFFFFF"
  brown: "#855F3C"
  amber: "#C79A28"
typography:
  largeTitle:
    fontFamily: SF Pro
    fontSize: 26px
    fontWeight: 700
  title:
    fontFamily: SF Pro
    fontSize: 17px
    fontWeight: 600
  headline:
    fontFamily: SF Pro
    fontSize: 13px
    fontWeight: 700
  body:
    fontFamily: SF Pro
    fontSize: 13px
    fontWeight: 400
  callout:
    fontFamily: SF Pro
    fontSize: 12px
    fontWeight: 400
  subhead:
    fontFamily: SF Pro
    fontSize: 11px
    fontWeight: 400
  caption:
    fontFamily: SF Pro
    fontSize: 10px
    fontWeight: 400
  caption2:
    fontFamily: SF Pro
    fontSize: 10px
    fontWeight: 400
  label:
    fontFamily: SF Pro
    fontSize: 11px
    fontWeight: 500
  overline:
    fontFamily: SF Pro
    fontSize: 10px
    fontWeight: 800
  mono:
    fontFamily: SF Mono
    fontSize: 10px
    fontWeight: 400
  monoBody:
    fontFamily: SF Mono
    fontSize: 13px
    fontWeight: 400
  monoCallout:
    fontFamily: SF Mono
    fontSize: 12px
    fontWeight: 400
  serifTitle:
    fontFamily: New York
    fontSize: 15px
    fontWeight: 400
  wordDisplay:
    fontFamily: SF Pro
    fontSize: 22px
    fontWeight: 600
  wordDisplayLarge:
    fontFamily: SF Pro
    fontSize: 28px
    fontWeight: 600
  studyWord:
    fontFamily: New York
    fontSize: 52px
    fontWeight: 600
  studyMeaning:
    fontFamily: SF Pro
    fontSize: 22px
    fontWeight: 600
  studyContext:
    fontFamily: New York
    fontSize: 17px
    fontWeight: 400
rounded:
  cell: 1.3px
  hairline: 2px
  cover: 3px
  xs: 4px
  sm: 6px
  md: 10px
  lg: 14px
  xl: 20px
spacing:
  hairline: 1px
  xxs: 2px
  xs: 4px
  sm: 8px
  md: 12px
  lg: 16px
  xl: 24px
  xxl: 32px
  xxxl: 48px
components:
  card:
    rounded: "{rounded.md}"
    padding: "{spacing.md}"
  panel:
    rounded: "{rounded.lg}"
  reading-overlay:
    backgroundColor: "{colors.reading-overlay}"
  button-quiet:
    height: 26px
  sidebar:
    width: 260px
  inspector:
    width: 420px
---

## Overview

RELL is a macOS reader for language learners: a book or PDF is read in a page-themed reading column, the Inspector beside it explains the selected word or sentence, and a separate study room reviews saved words. The interface follows one calm, consistent language: macOS system controls and system colours carry the chrome, the accent the user chooses is the only brand hue, and everything that touches the text being read takes the colours of the page theme.

## Colors

- **Surfaces** are macOS system colours, not fixed values: `DS.Color.surface` (window background), `surfaceElevated` (cards, inputs) and `surfaceInset` (sunken areas, text fields). Containers use the fixed surface scale `panel`, `cardInset` and `cardSoft` instead of new opacities of these.
- **Text** uses four steps only: `textPrimary`, `textSecondary`, `textTertiary` (overline labels, hints) and `textDisabled`.
- **Accent** is the user's accent choice, falling back to the macOS accent. Tints of it come from `accentSubtle`, `accentMuted` and `accentStrong`.
- **Semantic** colours carry meaning only: `success`, `warning`, `danger`, and `warningSubtle` for inline warning banners. Reading difficulty always maps through `coverageTint` (comfortable → success, challenging → warning, demanding → danger) on every coverage surface.
- **Identity** colours: `star` marks a saved word everywhere, `kindle` marks words imported from a Kindle, and `violet` is the study room's second hue beside the accent. `brown` (etymology module, legal domain) and `amber` (usage-notes module) are the only fixed hues, for module and domain identity.
- **Borders** use `hairline`, or `hairlineStrong` where a border must read against busy content; anything stronger uses `separator` itself.
- **Reading overlay**: every control floating over the text being read is filled with `reading-overlay` for the current page theme, opaque, so it reads as part of the page.

## Themes

The app chrome follows the macOS light or dark appearance through the system colours above. The reading column follows the page theme instead; Original is the default. The overlay of Original stays light whatever the system appearance, because a dark bar over a white page reads as a hole in it.

| Page theme | `page-background` | `reading-overlay` |
| --- | --- | --- |
| Original | #EBEBEB | #FFFFFF |
| Paper | #F7F2E8 | #FFFDF7 |
| Sepia | #F5EDDB | #FBF5E6 |
| Gray | #595959 | #333336 |
| Dark | #000000 | #2A2A2A |
| Night | #0D0D0D | #1F1D1A |

On the Gray, Dark and Night themes, controls over the text use the dark colour scheme so their `.primary` and `.secondary` labels stay legible on the dark overlay.

## Typography

- Text uses a `DS.Typography` role, never a raw `.font(.system(size:))`. A genuine one-off (an emoji size) carries a `// DS-exempt: <reason>` comment on its line or the two above it.
- The serif roles (`serifTitle`, `studyWord`, `studyContext`) are for text that stands for the book itself — a saved word and its sentence on a study card — so it looks like the page it came from. Interface text stays in the system face.
- A saved word's term uses `wordDisplay`, or `wordDisplayLarge` when it is the single most prominent term on screen.
- Section labels are uppercase `overline` in `textTertiary` (`dsOverlineLabel()` or `DSSectionHeader`).
- Numbers that count or score use `DS.Typography.statNumber(_:weight:)`, rounded. Small fixed chrome text uses `micro(_:weight:)`, and icon glyphs use `icon(_:weight:)`; neither stands in for the other.

## Layout

- Spacing uses the `spacing` steps. An exact size between steps is a sum of steps (for example `sm` + `xxs`), never a new literal.
- The main window has three columns: sidebar, reading column and Inspector, at their default widths below; Settings has one fixed size for every tab so switching tabs does not resize the window.
- Anything over the text being read sits in one of three places: the top strip, beside the text, or the bottom lane under the page. The bottom lane (sentence translation, then the speech bar, then repeating aloud) shortens the page rather than covering it.
- A transient card over the reader floats in an overlay; it never sits in the stack that sizes the PDF or EPUB view, which resizes the web view and loops AppKit's layout.

## Elevation & Depth

- Three shadows only: `DS.Shadow.subtle`, `card` and `float`. Surfaces floating over the text use `float`.
- Glass (macOS 26) is for chrome with nothing to read behind it: the sidebar, the Inspector background, the Quick Lookup panel, toasts. On macOS 15 the same surfaces fall back to a material or a DS surface. Glass never sits over text being read.
- Every card and panel uses the same hairline stroke weight (`DS.CardStroke`).
- Gradients come from `DS.Gradient` (the dashboard's accent wash, the goal ring, chart fades). The study room is the one surface with its own: the card's band, the rating buttons and the summary's ground stay lively. Everywhere else surfaces are flat.

## Shapes

- Corners use the `rounded` steps: `cell` for heatmap cells, colour swatches and mini covers, `cover` for document covers, `md` for cards and `lg` for panels and floating cards.
- Floating bars over the text (selection bar, speech bar) are capsules.

## Components

- **Buttons**: primary is the system `.borderedProminent` and secondary `.bordered`; the rest are DS styles — `.dsQuiet` (no fill, icon in the accent, label in the text colour), `.dsIcon` / `.dsIconSecondary`, `.dsChip(isOn:)` and `.dsChipTile(isOn:tint:)`. A screen has at most one primary button, for the step that moves on; actions in a row (Save, Listen, Anki) are quiet.
- **Hover and press** use one rule, `DS.Interaction.wash`, animated with `DS.Animation.fast`, with no animation under Reduce Motion; a disabled control fades to `DS.Interaction.disabledOpacity`.
- **Cards** use `dsCard()` and Inspector containers `dsPanel()`. Hand-made card chrome needs a `// DS-exempt:` note.
- **Shared views**: empty states use `DSEmptyState`, transient feedback `DSToast` / `dsToast`, reading progress `DSProgressBar`, and missing covers `DSCoverPlaceholder`.
- **Motion** uses `DS.Animation` curves and respects Reduce Motion through `DS.Animation.respecting` and `DS.slideTransition`.

## Do's and Don'ts

- Do use `DS` tokens for every colour, font, spacing and corner radius; the design-system audit test rejects raw fonts, numeric paddings and radii, and named colours outside `DS` unless the line carries `// DS-exempt: <reason>`.
- Don't put glass over text being read; use the opaque reading overlay.
- Don't put more than one primary button on a screen.
