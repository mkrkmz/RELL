# Changelog

All notable changes to RELL (Reader for Language Learner) are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com), and this
project follows [Semantic Versioning](https://semver.org).

## [1.27.0] - 2026-07-22

Engine parity and performance work, plus a first look at how well you're
actually retaining what you review. Roadmap v7 Sprint 3, and the first
slice of Sprint 4.

### Added

- **Two-up PDF view**: read facing pages side by side. Switch from the View
  menu or the menu bar's Page Layout submenu — your place in the document
  is preserved across the switch.
- **EPUB saved-word highlighting**: words you've saved are now underlined
  automatically as you read an EPUB, matching PDF's existing behavior.
  Click one to look it up, same as any other selection.
- **Review Accuracy** in Stats: a weekly accuracy chart with an overall
  retention trend line, a lifetime accuracy tile, and — once you're
  learning more than one language — a per-language word-count breakdown.

### Changed

- In-book EPUB search now scans the book chapter by chapter in the
  background instead of blocking on the whole thing at once, so results
  for a large book appear incrementally rather than all at the end.
- PDF auto-highlighting (saved words, notes) is noticeably cheaper while
  scrolling or zooming: the visible-page scan is debounced, page text is
  cached instead of re-extracted, and saving one new word no longer
  forces a full re-scan of every already-highlighted page.

## [1.26.0] - 2026-07-20

A visual consistency pass and a brand-new app icon. Second and final
sprint of roadmap v7.5 (Theme & Visual).

### Changed

- **New app icon** — a clean open-book mark on a blue gradient, finally
  legible at small sizes (the old icon embedded a wordmark that turned
  to mush at 16px). Regenerable from `scripts/generate-appicon.swift`.
- Learning-status colors (mastery, CEFR badges, review status) now
  route through the design system's semantic palette, so they harmonize
  with your chosen accent color instead of hardcoding blue/orange/green.
- The saved-word star is one consistent gold everywhere; the streak
  flame no longer switches hue between the dashboard and the stats
  sheet; note/bookmark swipe actions follow your accent color.
- Card chrome (borders, corners, shadows) is now drawn by one shared
  component across the dashboard, stats, onboarding, quiz, and
  inspector — the subtle border drift between screens is gone.
- Three deliberate gradients add depth where it counts: the
  continue-reading hero card, the daily-goal ring, and the vocabulary
  growth chart's area fill. All follow your accent color.
- The dashboard word card's flip now uses the same animation curve as
  the review flashcard.

## [1.25.0] - 2026-07-20

The app finally has its own sense of color, and reading got an appearance
panel worthy of a reading app. First sprint of roadmap v7.5 (Theme & Visual).

### Fixed

- **The page-theme picker in Settings ▸ Appearance never did anything.**
  It was writing to a preference key nothing else read. It now controls
  the actual reading theme, and gained App Theme and Accent Color
  controls alongside it.
- Choosing Light or Dark app theme now applies to *every* window —
  Settings, the Vocabulary Review window, the menu-bar Quick Lookup —
  not just document windows.

### Added

- **Accent color picker**: choose among ten accent colors (or follow the
  system) in Settings ▸ Appearance. The whole interface — buttons,
  links, badges, selection rings, native controls — follows instantly.
- **Three new page themes**: Paper (soft warm white), Gray (low-glare
  mid-gray), and Night (a warmer, gentler dark) join Original, Sepia,
  and Dark — for PDFs and EPUBs alike.
- **A reading-appearance panel** behind a new "Aa" toolbar button: theme
  swatches for both formats, plus EPUB typography — font family
  (Charter, Georgia, Palatino, Baskerville, Helvetica Neue, San
  Francisco, or the publisher's own), line height, column width, and
  justified text. Everything applies live as you read.

## [1.24.0] - 2026-07-17

Your library can now be organized into collections and pinned to the top,
and your saved words remember which language they're actually in. Second
sprint of the UI roadmap v7.

### Added

- **Pin documents** in the library so they stay easy to find — pinned
  documents survive the 48-document trim and always sort to the top,
  regardless of the chosen sort order.
- **Collections**: group library documents into named folders via
  right-click ▸ Add to Collection. Manage (rename/delete) them from the
  same menu; deleting a collection just un-groups its documents, it
  never removes them from the library.
- New filter chips above the library grid: All, Pinned, PDF, EPUB, and
  one per collection.
- Saved words now remember the language you were learning when you
  saved them, shown as a small flag next to the CEFR badge. A language
  filter appears in Saved Words once more than one language is present.
- Bulk actions in Saved Words: assign CEFR level, mastery, or language
  to every selected word at once.
- The bulk Anki export sheet can now be scoped by deck, CEFR level,
  mastery, or language before you pick individual cards — handy once
  your vocabulary spans more than one book or language.

## [1.23.0] - 2026-07-17

The AI panel now actually works in all 12 supported languages, not just
English and Turkish. First sprint of the UI roadmap v7.

### Fixed

- **Collocations were broken for every native language except Turkish.**
  The prompt hardcoded Turkish labels and demanded a Turkish translation
  regardless of your actual native language, and the parser only
  recognized those Turkish labels — so learners with any other native
  language got raw fallback text instead of parsed collocation cards.
- Explanation modules (Definition, Examples, Etymology, Pronunciation,
  Mnemonic, Synonyms, Word Family, Usage Notes) were hardcoded to always
  explain in English, regardless of what language you're actually
  studying. They now follow your target language.

### Added

- Saved words without a CEFR level now get one automatically in the
  background when you save them, using the same local/cloud model you
  already have configured. A "Estimate Missing Levels" action in Saved
  Words backfills existing words in bulk. Auto-estimated levels show a
  small sparkle marker; assigning a level yourself always wins and is
  never overwritten.
- The LLM API key now lives in the Keychain instead of plaintext
  UserDefaults — a one-time silent migration moves any existing key on
  first launch.

### Changed

- CLAUDE.md's LLM architecture notes were rewritten to match reality
  (four providers, retry/circuit-breaker resilience, health monitoring,
  the 50-entry disk-persisted cache) — they had drifted since v1.8.

## [1.22.0] - 2026-07-14

Text-to-speech now speaks in the language you're actually learning, not
always English, and you can pause it, stop it, or read a whole page at
once. Fourth and final sprint of the UI roadmap v6.

### Fixed

- **Speaking a selection always used an English voice, regardless of
  your target language.** Right-click ▸ Speak (PDF and EPUB) and the
  inspector's Speak button now use a voice matching whatever language
  you're actually studying, with a graceful fallback if that exact
  voice isn't installed.

### Added

- **Speech ▸ Read Page Aloud** (⌥⌘R) reads the whole current page (PDF)
  or chapter (EPUB), not just a selection — with Pause/Resume (⌥⌘P)
  and Stop (⌥⌘.) alongside it in the same menu.
- A floating playback bar appears at the bottom of the window whenever
  something is being read: pause/resume, stop, a progress bar, and a
  quick Slow/Normal/Fast rate picker.
- A Speech section in Settings ▸ General exposes the speaking rate as
  a slider — it was already stored, just never surfaced anywhere.
- Long text is now split into sentences and queued instead of being
  hard-cut at 500 characters — pauses land at natural sentence breaks,
  and whole-page reads aren't truncated at all.

## [1.21.0] - 2026-07-14

Library and saved-words search finally have parity, right-clicking a document
card gets you an actual Open item, and hovering a library cover reads a
little more alive. Third sprint of the UI roadmap v6.

### Added

- Right-clicking a library cover, the dashboard's "Continue reading" card,
  or a recent-document row now shows **Open** as the first item — not
  just Show in Finder — so it works the same way Finder's own context
  menus do.
- Shift-⌘F focuses the Library or Saved Words search field, whichever
  is currently visible.

### Changed

- The Library and Saved Words search fields share one implementation
  now instead of two that had quietly drifted apart: both get a clear
  button, a hairline border, and Esc-to-clear (an empty field lets Esc
  fall through to whatever it normally does, like Library's Back).
- Library's "no results" state now uses the same shared empty-state
  layout as everywhere else in the app, instead of its own one-off
  version.
- Hovering a library cover now lifts very slightly instead of just
  swapping its border color, unless Reduce Motion is on.
- A few context-menu labels ("Show in Finder", "Document Stats…",
  "Remove from Library") that were only ever in English are now
  properly localized.

## [1.20.0] - 2026-07-13

A mechanical but overdue cleanup: every fixed-size font in the app now goes
through one shared declaration instead of being retyped at each call site.
Second sprint of the UI roadmap v6.

### Changed

- All ~65 icon glyph sizes (`Image(systemName:)` throughout the reader,
  inspector, library, and quiz) now go through a single shared
  `DS.Typography.icon(_:weight:)` declaration instead of each spelling
  out its own `.font(.system(size:...))`. Visually identical — this is
  about having one place to change icon sizing, not a redesign.
  The library search field's font, the Quick Lookup HUD's search text,
  and a saved word's flashcard-front size now use real text styles
  (`.title2`, `DS.Typography.title`) instead of a hardcoded point
  size, so they scale with the system's text-size setting.
- Introduced the `// DS-exempt: <reason>` convention for the rare
  literal one-off (a language flag emoji) that has no meaningful
  shared token — documented in CLAUDE.md so it doesn't get
  re-litigated next time someone greps for raw font sizes.

## [1.19.0] - 2026-07-13

The blue-rectangle flashcard fix, plus feedback for every silent action.
First sprint of the UI roadmap v6.

### Fixed

- **A blue rectangle no longer appears around Review flashcards.** The
  keyboard-accessibility work in 1.17 made the card focusable, which
  also made macOS draw its system focus ring around the whole card.
  The ring is now suppressed; flipping with Space/Return, tapping, and
  the VoiceOver labels all still work exactly as before.

### Added

- Actions that used to complete in silence now confirm with a brief
  toast: saving a word from the PDF or EPUB right-click menu, adding or
  removing a bookmark (⌘B), and saving a word from a note — including
  honest variants when the word was already saved or just re-queued
  for review.

### Changed

- The Review mode picker (Flashcard/Choice/Type), inspector mode tabs,
  Anki export domain tags, LLM provider names, and the Library sort menu
  are now properly localized — they previously showed raw English labels
  even on Turkish systems.
- The saved-words panel's four empty states (no words yet, none in this
  document, nothing to review, no search matches) now use the shared
  empty-state component instead of a hand-rolled layout.
- The last stray hand-picked border opacities moved onto the design
  system's two-step hairline scale, so card faces, chart grid lines, and
  swatch rings read consistently in both light and dark mode.

## [1.18.0] - 2026-07-12

Motion polish and a real bug fix: reading position restore had a gap that
could leave you back on page 1. Fourth sprint of the UI/UX roadmap.

### Fixed

- **Reopening a document from the dashboard could silently forget your
  page.** The reading-position restore only ever listened for a document
  change inside an already-open reader; clicking a dashboard card opens
  a document through a different path that never triggered it, so a
  freshly launched window always landed on page 1 regardless of where
  you left off. Restore now fires from the actual place a window adopts
  its document, with a timeout fallback so it can't silently break again.

### Changed

- Showing/hiding the sidebar, inspector, and Focus Mode now animate
  instead of snapping, with a matching curve in both directions.
- The onboarding flow's steps slide in from the direction you're
  navigating — forward on Continue, backward on Back — instead of a flat
  cross-fade.
- The Annotations sidebar now fades between Marks/Highlights/Notes
  instead of hard-cutting.
- All motion in the app now respects **Reduce Motion** (System Settings
  → Accessibility): the above transitions fall back to a plain fade or
  no animation at all when it's on.
- A handful of ad-hoc animation durations scattered across the inspector
  status dot, the quiz flashcard flip, and the streaming "Generating…"
  indicator now share the same three or four named curves as everything
  else, instead of each hardcoding its own.

## [1.17.0] - 2026-07-12

Every action that lived only on a toolbar button or a right-click now also
has a menu-bar home — so it's discoverable, keyboard-reachable, and shows
up correctly for full-keyboard-access and VoiceOver users. Third sprint of
the UI/UX roadmap.

### Added

- **Edit menu:** Find… (⌘F), Find Next (⌘G), Find Previous (⇧⌘G) — works
  for both PDF and EPUB.
- **View menu:** Zoom In (⌘+), Zoom Out (⌘−), Actual Size (⇧⌘0), Fit to
  Width (⌘0, PDF only — EPUB reflows continuously, so this stays disabled
  there), a Page Theme submenu (Original/Sepia/Dark with a checkmark on
  the active one), Add/Remove Bookmark (⌘B), and Save Word/Remove from
  Saved (⌘D) — all reflecting live document state, including a properly
  toggling label ("Add Bookmark" ⇄ "Remove Bookmark", etc.).
- **File ▸ Open Recent ▸ Clear Menu** — empties the recent-documents list
  in one step; the files themselves are untouched.
- Flashcards in Review can now be flipped with Space or Return, not just
  a tap, and expose proper VoiceOver labels/hints. Multiple-choice options
  now announce whether they were correct or incorrect after you answer.
  Ask AI follow-up exchanges read as one coherent Q&A unit to VoiceOver
  instead of five disconnected fragments.

## [1.16.0] - 2026-07-12

Design-system cleanup: one consistent visual language across borders,
empty states, typography, and the Settings window. No new features —
this sprint is quality-of-life polish, second of the UI/UX roadmap.

### Changed

- **Card and panel borders are consistent.** Nine spots across the
  dashboard, onboarding, Quick Lookup HUD, EPUB find bar, and the reader
  toolbar were drawing their own slightly-different border opacity;
  they now all use the same `hairline` token the inspector already
  standardized on.
- **Settings no longer resizes when you switch tabs.** Each of the four
  tabs (General, LLM, Prompts, Appearance) had its own fixed height,
  so the window visibly jumped switching between them. One fixed size
  now covers all four, sized to the tallest (Prompts); shorter tabs
  just leave breathing room instead of resizing the window.
- Several empty states (the EPUB table-of-contents panel, the inspector's
  "select text" hint) now use the shared `DSEmptyState` component instead
  of a hand-rolled layout, and picked up proper Turkish translations in
  the process — `DSEmptyState` was silently skipping the string catalog
  for every literal call site since it took plain `String` instead of a
  localizable key.
- Recurring one-off sizes (dashboard cover art, Quick Lookup HUD width,
  the dashboard/library content columns, quiz-card heights) now live as
  named `DS.Layout` constants instead of scattered magic numbers.
- Added a small set of typography roles for patterns that were genuinely
  duplicated (a saved word's term shown large, rounded-digit stat
  numbers, tiny sidebar/badge chrome text) so those five call sites
  share one definition instead of five near-identical ones.
- The Annotations sidebar's "Marks / Highlights / Notes" segmented
  control is now actually localized — like `DSEmptyState`, it was
  building its labels with a raw `String`, which always shows English
  regardless of the system language.

## [1.15.0] - 2026-07-11

EPUB catches up: the last PDF-only annotation features now work in books,
plus a real dark-theme readability fix. First sprint of the UI/UX roadmap.

### Added

**EPUB bookmarks**
- The toolbar Bookmark button (⌘B) — previously disabled for EPUBs — now
  works in books. A bookmark captures your chapter and scroll position,
  plus the first visible line of text as its label. Press ⌘B again at the
  same spot to remove it. The Annotations sidebar's Marks segment lists
  them; tap a row to jump straight back. Bookmarks can carry a note, same
  as PDF bookmarks.

**EPUB notes**
- The Annotations sidebar's Notes segment now works for books: "New Note"
  captures a thought at your current reading position; tap a saved note
  to jump back to where you wrote it. Previously the segment showed an
  empty PDF panel for EPUBs.

### Fixed

- **Highlighted text is readable in the Dark page theme.** Highlight marks
  hardcoded near-black ink, which was illegible over a translucent mark on
  a dark page. The ink now follows the page theme — light ink in Dark,
  highlighter-dark ink in Original/Sepia — and re-renders when you switch
  themes.
- EPUB files opened before v1.9 could show their `.epub` extension in the
  dashboard and Library titles; extensions are now stripped for both
  formats via one shared helper.
- The Annotations tab badge for EPUBs now counts bookmarks + highlights +
  notes (was highlights only).
- Several bookmark/highlight empty-state messages (both formats) were
  never actually localized — they now resolve their Turkish translations.

### Notes

- An EPUB bookmark's position is approximate under reflow: changing the
  font size after bookmarking can shift the exact scroll target slightly.
  The captured text label always shows what was on screen at creation time.

## [1.14.0] - 2026-07-09

Learning-engine and AI-layer release, combining three sprints: smarter spaced
repetition, a daily reminder, richer AI lookups, and opt-in background
vocabulary warming.

### Added

**SRS ease factor**
- Each word now carries its own SRS ease multiplier (SM-2 style, starts at a
  neutral 2.5). Consistently marking a word "Again" shortens its future
  intervals; marking it "Easy" stretches them. Words untouched by this keep
  today's fixed review schedule exactly — the ease only scales the day-based
  intervals, not the short relearning steps.

**Daily reminder**
- New Settings toggle schedules a local daily notification at a time you
  choose, nudging you to hit your reading/review goal. Tapping it opens the
  Vocabulary Review window.

**Streak protection**
- The dashboard now flags when your reading streak is still alive but at
  risk — no session logged yet today — with a warning-colored "read today to
  keep it" hint next to the streak count.

**Quick Lookup HUD streaming + native meaning**
- The ⌃⌥Space HUD now streams the definition token-by-token instead of
  waiting for the full answer, and shows your native-language meaning as a
  subtitle underneath once it arrives. Both are saved together when you
  save the word.

**Ask AI follow-up thread**
- Follow-up questions now remember the last few turns of the conversation,
  so a second question like "what about its opposite?" resolves correctly
  instead of starting from zero context each time. Each answer also gets a
  one-click copy button.

**Page/chapter pre-analysis (off by default)**
- A new "Page Pre-Analysis" toggle in Settings → Reading Aids scans the
  visible page/chapter for likely-unfamiliar words (noun/verb/adjective,
  via on-device lexical tagging — no network call for the scan itself) and
  quietly pre-fetches their definitions in the background, so a later
  lookup is instant. Works in both PDF and EPUB. Disabled, it makes zero
  additional requests.

**CEFR level badge**
- Saved words can be tagged with a CEFR level (A1–C2) from the word list's
  context menu; the level shows as a colored badge in the row and can be
  used to filter the list.

### Fixed

- The "native-language meaning" module's system prompt hardcoded "Output
  only in Turkish" regardless of the learner's actual configured native
  language, contradicting its own user prompt for the other 11 supported
  languages. It now follows the real native-language setting.

## [1.11.0] - 2026-07-09

### Added

**EPUB highlights**
- EPUBs now support the same highlight-and-annotate workflow as PDFs.
  Select text, right-click, and choose a color from the Highlight
  submenu to mark a passage — the mark persists across chapter reloads
  and app relaunches, and survives font-size/window-resize reflow
  since it's anchored by a text-quote (surrounding context + offset)
  rather than fixed geometry.
- New **Highlights** segment in the EPUB sidebar (Annotations tab)
  lists every highlight for the open book, grouped by chapter. Tap a
  row to jump straight to that chapter and scroll the mark into view.
  Hover a row to add or edit a note, or recolor it; swipe or
  right-click to delete.

## [1.10.1] - 2026-07-08

### Fixed

- **EPUB page themes now work.** Sepia and Dark had no visible effect —
  the injected reader CSS only tinted the `<html>` background, so the
  publisher's own `body { background:#fff; color:#000 }` painted right
  over it and left the page white. The theme now forces the surface and
  cascades the text color through the book's text elements with
  `!important`, while the Original theme still leaves the book's own
  colors untouched.

## [1.10.0] - 2026-07-08

Learning-engine release, part one: the vocabulary backlog. Export to more
tools, organize decks in bulk, and annotate highlights.

### Added

**Export formats**
- Bulk export now offers three formats via a picker (your choice is
  remembered): **Anki TSV** (unchanged), **CSV** (plain-text spreadsheet
  with Front/Back/Tags/Source columns, RFC 4180 quoting), and **Quizlet**
  (exactly `term<TAB>definition` per line for Quizlet's import box, HTML
  stripped). The save dialog picks the right file type automatically.

**Bulk deck management**
- New **Select** mode in the Words list: check multiple words, then assign
  them to an existing deck, create a new deck on the spot, remove a deck,
  or delete them together — one click instead of word-by-word context
  menus. A select-all toggle covers the currently filtered list.

**Highlight notes**
- Highlights can now carry a note: hover a highlight row (or right-click)
  to add or edit one; notes show inline in the Highlights list and survive
  restarts. Older highlight files load unchanged.

### Changed

- Adding or removing a deck now refreshes the word's Spotlight entry, so
  deck names are immediately searchable system-wide.

## [1.9.2] - 2026-07-06

Quality pass: real localization bugs fixed, test coverage extended, and a
second CI type-check risk caught before it could bite a release.

### Fixed

- Sort/filter labels in the vocabulary list ("Newest", "This Document", …)
  and two "File not found" messages were silently never localized: they
  went through SwiftUI's plain-string `Text` initializer, which — unlike
  `Text` with a string literal — never consults the string catalog. These
  now resolve through `String(localized:)` / a `localizedTitle` property,
  matching the pattern already used for sidebar tab titles.
- `InspectorView.body` carried the same 24-modifier single-chain shape
  that caused the v1.9.0 CI type-check timeout. Split into staged
  modifier groups before it could fail the same way.

### Added

- Unit tests for `SpotlightIndexer` (identifier/deep-link round-trip),
  `ReadingSessionStore` (session lifecycle, streaks, 7-day stats),
  `QuickLookupPanelModel` (cache-hit lookup, save, reset), and
  `EPUBSearchManager` (match counting, snippets) — all previously
  untested code from the S3–S8 and EPUB work.

### Changed

- `CLAUDE.md` and `ARCHITECTURE.md` no longer describe RELL as PDF-only
  or claim zero test coverage / no structured logging — both were stale.

## [1.9.1] - 2026-07-06

A wording pass following EPUB support: the interface (and README) no longer
assumes every open document is a PDF.

### Fixed

- The dashboard's continue-reading card showed **"Page 11 of 28"** for an
  open EPUB — it now says **"Chapter 11 of 28"**. `RecentDocument` derives
  the wording from the file extension.
- "Open PDF", "Start with a PDF", "This PDF" (vocabulary filter), and
  similar labels across the empty state, toolbar, onboarding, and export
  sheet are now format-neutral ("Open", "This Document", …) since they
  apply to both PDFs and EPUBs. Turkish translations updated to match.
- README (English and Turkish) now describes RELL as a PDF **and EPUB**
  reader throughout — feature list, keyboard shortcuts, project structure,
  and tech stack table.

Empty-state messages for **notes, bookmarks, and highlights** still say
"Open a PDF" — those three features remain PDF-only for now, so the
wording is accurate as-is.

## [1.9.0] - 2026-07-03

RELL learns to read EPUBs. Books get the full vocabulary workflow — select,
analyze, save, review — with zero new dependencies.

### Added

**EPUB reading**
- Open `.epub` books (Open panel, drag & drop, Open Recent, multi-window
  tabs — everything PDFs already do). Built on a dependency-free EPUB
  engine: an in-house read-only ZIP decoder plus an EPUB 2/3 package parser.
- Chapter-based reading with scroll position memory per book; ⌥⌘←/→
  moves between chapters; the sidebar's Contents tab shows the book's
  table of contents (EPUB3 nav with NCX fallback), with the current
  chapter highlighted.
- Page themes (Original / Sepia / Dark) apply to books via injected CSS;
  ⌘+/− adjusts **text size** (12–28 px) instead of zoom.
- The window title shows the book's real title; the dashboard shows the
  book's cover (from the EPUB's declared cover image).

**Vocabulary workflow in books**
- Selecting text in a book drives the Inspector exactly like in PDFs:
  auto-run analysis, all ten modules, Ask AI, sentence translation strip.
  The surrounding sentence is captured as context for prompts and saved
  words.
- Right-click menu in books: Save Word, Look Up in Inspector,
  Analyze With ▸ (all ten modules), Speak.
- **Hover dictionary works in books:** rest the pointer on a word for a
  quick definition, exactly like in PDFs (same cache, same setting).
- Saved words record the book and chapter as their source; Spotlight
  indexes books alongside PDFs.

**In-book search**
- ⌘F in a book searches the whole text: per-chapter results with match
  counts and snippets; click a result to jump to that chapter with the
  match highlighted. ⌘G / ⇧↩ steps through matches in the open chapter.

**Progress**
- The status strip shows "Chapter 3 / 28 · 42%"; the dashboard's
  continue-reading cards track book progress by chapter.

Compatibility verified against Project Gutenberg (EPUB3 and legacy) and
Standard Ebooks productions.

### Known limitations (by design, for now)

- No DRM (Adobe/LCP) and no fixed-layout EPUB3 support.
- Highlights, notes, and page bookmarks are not yet available in books
  (PDF unaffected).

## [1.8.0] - 2026-07-03

The structural release: RELL becomes a true multi-window Mac app with native
panels, speaks Turkish, and plugs into Spotlight, Shortcuts, and the
Services menu.

### Added

**Multiple windows & native tabs**
- Each PDF opens in its own window; opening a second document while one is
  on screen opens it **side by side — as a native tab by default** (drag the
  tab out for a separate window; Window › Merge All Windows works).
- Opening an already-open PDF focuses its window instead of duplicating it.
- ⌘N opens a new dashboard window; File › Open Recent opens documents in
  their own window/tab; windows restore after relaunch.
- New standalone **Vocabulary Review window** (Go › Vocabulary Review, ⌥⌘V) —
  study without a document open.
- Reading-time tracking is now focus-aware: the active window's document
  owns the session.

**Turkish localization & accessibility**
- The interface is localized into Turkish (menus, toolbar, sidebar,
  settings, Quick Lookup, status surfaces, context menus) via a String
  Catalog — follows the system language.
- Tooltips on sidebar tabs and module buttons; VoiceOver labels for zoom
  and iconic controls.

**System integration**
- **Services menu:** select text in any app → Services → "Look Up in RELL"
  opens the Quick Lookup panel with the selection.
- **Shortcuts (App Intents):** three actions — *Add Word to RELL*,
  *Start Vocabulary Review*, *Look Up in RELL* — usable from Shortcuts
  and Spotlight.
- **Core Spotlight:** saved words and library documents are searchable
  system-wide. Clicking a word result opens its card in the Words tab;
  clicking a document reopens the PDF.

### Changed

- The three-panel layout now uses the native `NavigationSplitView` and
  inspector APIs: standard resize behavior, system sidebar toggle, and
  column widths remembered by macOS. The custom divider is gone.
- Shared stores (words, bookmarks, notes, highlights, recents, covers)
  moved to app scope — all windows and the Quick Lookup surfaces see the
  same data instantly.

### Fixed

- Saved-words list no longer overflows the sidebar when the panel is
  narrow: the filter bar compresses and wraps instead of clipping the
  whole list.

## [1.7.1] - 2026-07-02

RELL grows into the Mac: full menu bar coverage, a system-wide Quick Lookup
panel, module access from the right-click menu, and an LLM status light in
the toolbar.

### Added

**Quick Lookup HUD**
- **⌃⌥Space anywhere on the system** opens a floating lookup panel (uses
  Carbon hotkeys — no Accessibility permission needed). Type a word, press
  Return, get the definition; ⌘S saves it to your vocabulary, Esc closes.
- The panel is cache-first: saved words and recently hovered terms answer
  instantly without an LLM request; it never activates the app or steals
  your current window's focus.
- Speak button reads the term aloud; already-saved terms show a "Saved" badge.
- New menu bar icon opens the same lookup panel even when no RELL window is
  open. Settings › General › Quick Lookup has toggles for the icon and the
  shortcut.

**Menu bar**
- **File** gains Open Recent (last 12 documents) and Close Document (⇧⌘W).
- **View** gains Show/Hide Sidebar (⌘⌥S), Show/Hide Inspector (⌘⌥I), and
  Enter/Exit Focus Mode (⇧⌘D) — titles flip with the current state.
- New **Go** menu: Previous/Next Page (⌥⌘← / ⌥⌘→), enabled only when there
  is somewhere to go.
- New **Modules** menu: all ten analysis modules with ⌘1–⌘9 shortcuts, plus
  Run Last Module (⌘L). Items disable when nothing is selected.
- Menu commands reach the key window through SwiftUI FocusedValues
  (`ReaderCommands`), not notifications.

**Context menus**
- PDF right-click menu gains **Analyze With ▸** — pick any of the ten modules
  directly from the selection; the Inspector opens automatically if hidden.
- Thumbnail sidebar right-click: Bookmark Page and Copy Text from Page.

**LLM status**
- Toolbar status light (green/orange/red dot + model name) with a popover
  showing provider, server, model, latency, and last check time.
- Reachability probe runs at launch and whenever the provider, server URL,
  or model changes — problems surface before the first failed request.
- The Inspector's "server unreachable" banner now has a **Settings…** button
  that deep-links to the LLM pane; the status popover does the same.

### Changed

- The hover dictionary, sentence translation strip, and Quick Lookup now
  share one definition cache and one request gate, so a word looked up in
  any surface is instant in the others.

### Fixed

- Opening the Inspector while text was already selected no longer shows the
  empty "Select text to analyze" state — the live selection is adopted on
  mount.
- Keyboard shortcuts moved from hidden toolbar buttons to real menu items,
  so they are discoverable and survive toolbar customization.

## [1.7.0] - 2026-07-02

A Review Center release: study modes are now genuinely testing recall, and
review cards finally show everything you saved for a word.

### Changed

**Study modes**
- **Choice** now works from definition to word: the card shows the saved
  definition with the word masked out (•••), and you pick the right word among
  four saved terms. The old direction gave itself away — definitions quote the
  word, and the word sat right above the options.
- **Type** is now a fill-in-the-blank exercise: the saved context sentence
  appears with the word blanked, plus a masked definition as a hint, and your
  answer is checked objectively (✓ Correct / ✗ Not quite) instead of the old
  advisory self-check.
- Words without a usable definition or sentence gracefully fall back to a
  plain flashcard reveal, as before.

**Review cards**
- The card back now shows **every** saved module: Definition and native
  meaning appear first, and a "Show more (N)" button reveals the rest
  (etymology, collocations, examples, synonyms, …), each labeled with its
  module color and name.
- Long card content scrolls inside the card instead of clipping in the
  narrow sidebar.

### Fixed

- Spaced-repetition scheduling, cram mode, deck filters, and keyboard
  shortcuts are untouched; the stored mode preference carries over.

## [1.6.0] - 2026-07-01

A focused release on the word inspector: local LLM streaming feels faster and
never looks stalled, and the inspector panel gets a visual-hierarchy pass.

### Changed

**Inspector**
- Redesigned the inspector layout for clearer hierarchy: the word + actions,
  explain controls, modules, and result now read as distinct zones.
- Header actions are grouped into a clean toolbar (speak on the left, save and
  more on the right); recent terms moved to a quieter secondary row.
- The module grid gains a **MODULES** section label, and **Run All** is now a
  distinct labeled action instead of a look-alike module button.
- Card surfaces and borders across the inspector are unified onto a single
  surface/hairline system for a more cohesive look.

**Streaming**
- Definition and meaning now stream directly into their "In This Context" /
  "General Meaning" cards, so the layout no longer reshuffles when the
  response finishes.

### Fixed

- Local models no longer stall mid-answer: hidden reasoning tokens are now
  suppressed for **all** local servers (LM Studio and Ollama, any port), not
  just LM Studio on its default port — removing the multi-second gaps where a
  few sentences appeared and the rest arrived late.
- A live **"Generating…"** indicator now animates at the end of the streaming
  text (and the header status dot pulses again), so a paused response no longer
  looks finished.

## [1.5.0] - 2026-06-25

A large feature release. RELL gains a study-focused home dashboard, new in-page
reading aids, a full vocabulary practice system, faster and more reliable local
LLM responses, and a cleaner two-panel layout.

### Added

**Home dashboard**
- A calm welcome dashboard when no PDF is open: a "Continue reading" hero card,
  a single review prompt, and a quiet recent-documents list.
- PDF cover thumbnails rendered from each document's first page (cached on disk).
- A daily reading-goal ring with a 7-day activity chart and reading streak;
  the goal is adjustable from the card.
- An inline flip word card to review a due word without leaving the dashboard.
- A cover-grid **Library** view ("View all") with search and sorting.
- A three-step first-run **onboarding** flow (language pair → AI connection
  test → quick tour), reopenable from Settings.

**Reading aids**
- **Focus mode** (⇧⌘D) hides the side panels for distraction-free reading.
- **Persistent highlights** in five colors, with a right-click color menu and a
  dedicated list; highlights are saved per document.
- **Hover dictionary**: pause over a word to see a quick definition popover
  (cache-first, then a short lookup).
- **Sentence translation strip**: select a sentence to see a native-language
  translation below the page.

**Vocabulary & review**
- **Tags / decks** for saved words, with deck filtering in the word list and
  deck-scoped review sessions; tags are included in Anki export.
- New quiz modes — **multiple choice** and **typed recall** — plus a **cram**
  mode that drills cards without changing the spaced-repetition schedule.
- **Text-to-speech** pronounce buttons on quiz cards, saved-word rows, and the
  dashboard card.

**AI & stats**
- **Ask AI** follow-up thread in the inspector, grounded in the selected term,
  its sentence, and the active module output.
- Vocabulary-growth and mastery-distribution charts in Stats, and a per-document
  stats sheet (reading time, saved/due words, notes, bookmarks, progress).

### Changed

- **Sidebar simplified from 8 tabs to 4** — Pages, Contents, Annotations, Words.
  Bookmarks, highlights, and notes merge under **Annotations**; the saved list
  and review session merge under **Words** (each with a segmented switcher).
- **Stats moved out of the sidebar** to a toolbar button that opens it in a sheet.
- **Inspector action bar decluttered** — only Save and Speak stay visible; copy,
  export, and clear move into an overflow (⋯) menu; the settings gear is removed.
- **Module grid** shows five primary modules with the rest behind a "More"
  disclosure, replacing the dimmed overflow row.
- **Flatter inspector** — nested card borders collapse to a single result card
  plus a light Ask-AI input.
- A **Home** button (⇧⌘W) returns to the dashboard while reading.
- LLM output now persists in a cache across launches, surviving app restarts.

### Performance

- Truncation is detected from the server's `finish_reason` instead of a
  character heuristic, so the "incomplete output" warning is accurate.
- Concurrent requests to local servers (LM Studio / Ollama) are queued so
  "Run All" no longer floods the GPU.
- Per-module token budgets were raised for mid/large local models (12B+),
  reducing spurious cut-offs; small-model caps still apply.
- Result parsing is memoized and streaming re-renders are throttled.

### Fixed

- Sidebar tab icons now align consistently; the Contents tab uses a symmetric
  symbol that also shows correctly in its selected (filled) state.
