# Changelog

All notable changes to RELL (Reader for Language Learner) are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com), and this
project follows [Semantic Versioning](https://semver.org).

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
