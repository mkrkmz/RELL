# Changelog

All notable changes to RELL (Reader for Language Learner) are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com), and this
project follows [Semantic Versioning](https://semver.org).

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
