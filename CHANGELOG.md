# Changelog

All notable changes to RELL (Reader for Language Learner) are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com), and this
project follows [Semantic Versioning](https://semver.org).

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
