//
//  QuizView.swift
//  Reader for Language Learner
//
//  Flashcard-style quiz over saved words.
//  Front: term. Back: definition (or first available LLM output).
//  "Know it" → mastery++, "Again" → stays in queue.
//

import SwiftUI

struct QuizView: View {
    var store: SavedWordsStore
    /// The sidebar's quick review, or the study room's window (v15 S2) —
    /// same card modes; the room has its own setup, summary, larger cards
    /// and the arrow keys.
    var style: Style = .sidebar
    var onContinueReading: (() -> Void)? = nil
    var onOpenSavedWords: (() -> Void)? = nil
    /// Set by modal hosts (the dashboard review sheet): shows a close button
    /// and binds Esc, so the quiz can be left mid-session. Window/sidebar
    /// hosts leave it nil — they already have their own exit.
    var onClose: (() -> Void)? = nil
    /// A book's words (v16 S1): the sidebar reviews only these.
    var scopeIDs: Set<UUID>? = nil
    /// Nothing waiting in the book: study every word instead.
    var onStudyAll: (() -> Void)? = nil

    /// Queue, position, tallies and the card's answer state — see `QuizSession`.
    @State var session = QuizSession()
    /// A sentence card's text is shown (T) before the translation (v19 S2).
    @State var sentenceTextShown = false

    /// Sentences met in reading, for cloze contexts. Optional: a host without
    /// the encounter log still quizzes from the saved sentence alone.
    @Environment(WordEncounterStore.self) var encounterStore: WordEncounterStore?
    /// The dictionary's answer for a card with nothing on its back (v15 S1).
    @Environment(WordEnricher.self) var enricher: WordEnricher?
    /// The book read last, for the study room's "This book".
    @Environment(RecentDocumentStore.self) var recentDocuments: RecentDocumentStore?
    @AppStorage(StorageKey.studySentenceOnFront) var sentenceOnFront = true
    @FocusState var roomFocused: Bool

    // Filter: due words only by default
    @State var includeAll = false
    @State var selectedTag: String?

    // Modes
    @AppStorage(StorageKey.quizMode) var quizModeRaw = QuizMode.flashcard.rawValue
    /// In the modes the app can check itself, let the check be the grade
    /// instead of asking the user to judge an answer already marked ✓ or ✗.
    @AppStorage(StorageKey.typedAutoGrade) var typedAutoGrade = true

    /// Modules shown on the card back by default; the rest sit behind "Show more".
    static let summaryModules: [ModuleType] = [.definitionEN, .meaningTR]

    /// The exercise of the card on screen: the chosen mode, or what
    /// "By Stage" picked for this word (v15 S3).
    var cardMode: QuizMode {
        quizMode == .mixed ? (session.currentMode ?? .flashcard) : quizMode
    }

    var quizMode: QuizMode {
        let stored = QuizMode(rawValue: quizModeRaw) ?? .flashcard
        // A stored mode can become unofferable — the voice it needs may have
        // been removed since it was last chosen.
        return availableModes.contains(stored) ? stored : .flashcard
    }

    /// Modes that can actually be run right now. Listening is dropped when the
    /// system has no voice for anything in the vocabulary: without one,
    /// AVSpeech reads the word in the wrong language, which teaches the wrong
    /// pronunciation — worse than not offering the mode.
    var availableModes: [QuizMode] {
        QuizMode.allCases.filter { mode in
            switch mode {
            case .listening: return canSpeakVocabulary
            // A grid of fewer than four pairs plays itself, so the mode is
            // only offered once enough saved words carry a definition.
            case .matching:  return matchableWords.count >= MatchingRound.minimumPairs
            // Writing needs the room's large card (v19 S3).
            case .write:     return style == .room
            default:         return true
            }
        }
    }

    /// Words in the current queue that could take a place on a matching grid.
    /// The run is built from these rather than filtered per grid: a slice of
    /// the full queue can fall below the minimum even when the vocabulary
    /// doesn't, which would strand the round with nothing to pair.
    var matchableWords: [SavedWord] {
        var seen: Set<String> = []
        return wordsToQuiz.filter { word in
            guard word.usableDefinition != nil else { return false }
            let term = word.term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !term.isEmpty && seen.insert(term).inserted
        }
    }


    // MARK: - Quiz Card

    @ViewBuilder
    var quizCard: some View {
        if let word = session.currentWord {
            quizCard(for: word)
        }
    }

    func quizCard(for word: SavedWord) -> some View {
        VStack(spacing: DS.Spacing.lg) {
            VStack(spacing: DS.Spacing.xs) {
                ProgressView(value: Double(session.position), total: Double(session.total))
                    .tint(DS.Color.accent)
                HStack {
                    Text("Review \(session.position) of \(session.total)")
                    Spacer()
                    if session.cram {
                        Label("Cram", systemImage: "bolt.fill")
                            .foregroundStyle(DS.Color.warning)
                    }
                    Label(word.reviewStatus.label, systemImage: word.reviewStatus.icon)
                        .foregroundStyle(word.reviewStatus.color)
                }
                .font(DS.Typography.caption2.weight(.semibold))
                .foregroundStyle(DS.Color.textTertiary)
            }
            .padding(.horizontal, DS.Spacing.md)
            // Keep the progress bar clear of the floating close button.
            .padding(.trailing, onClose != nil ? DS.Spacing.xl : 0)

            Spacer()

            switch cardMode {
            case .flashcard:      flashcardBody(word)
            case .multipleChoice: multipleChoiceBody(word)
            case .typed:          typedBody(word)
            case .listening:      listeningBody(word)
            // Round-based modes never reach the single-card frame.
            case .matching, .mixed, .write: EmptyView()
            }

            Spacer()

            if session.isFlipped {
                if showsRatingRow {
                    ratingRow(for: word)
                } else {
                    autoGradeContinueRow(for: word)
                }
            }
        }
        .padding(.vertical, DS.Spacing.md)
        .animation(DS.Animation.springFast, value: session.isFlipped)
    }

    // MARK: - Flashcard Body

    @ViewBuilder
    func flashcardBody(_ word: SavedWord) -> some View {
        ZStack {
            cardFace(content: backContent(for: word), isFront: false)
                .rotation3DEffect(.degrees(session.isFlipped ? 0 : -90), axis: (x: 0, y: 1, z: 0))
                .opacity(session.isFlipped ? 1 : 0)

            cardFace(content: frontContent(for: word), isFront: true)
                .rotation3DEffect(.degrees(session.isFlipped ? 90 : 0), axis: (x: 0, y: 1, z: 0))
                .opacity(session.isFlipped ? 0 : 1)
        }
        .onTapGesture { flipCard() }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space) { flipCard(); return .handled }
        .onKeyPress(.return) { flipCard(); return .handled }
        .onKeyPress(.escape) {
            guard style == .room || onClose != nil else { return .ignored }
            handleEscape()
            return .handled
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(session.isFlipped ? "Card back" : "Card front")
        .accessibilityHint("Press space or return to flip")

        if !session.isFlipped && style == .sidebar {
            Text("Tap to reveal")
                .font(DS.Typography.caption2)
                .foregroundStyle(DS.Color.textTertiary)
        }
    }


    // MARK: - Rating Row

    /// Whether the user grades this card themselves. In the modes the app
    /// checks itself, auto-grading replaces the four buttons with a single
    /// Next — the answer was already objectively right or wrong, and asking
    /// the user to re-judge it is busywork. Turning the setting off restores
    /// the four buttons, which is the only way to reach Hard/Easy.
    var showsRatingRow: Bool {
        !(cardMode.isObjectivelyGraded && typedAutoGrade)
    }

    /// The auto-graded alternative to `ratingRow`: the grade is decided, this
    /// just applies it and moves on.
    func autoGradeContinueRow(for word: SavedWord) -> some View {
        let isCorrect = QuizMatching.matchesTerm(typed: session.typedAnswer, term: word.term)
        return Button {
            recordRating(isCorrect ? .good : .again, word: word)
        } label: {
            Label("Next", systemImage: "arrow.right")
                .font(DS.Typography.callout.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .keyboardShortcut(.defaultAction)
        .padding(.horizontal, DS.Spacing.xl)
        .help(isCorrect ? "Graded correct — continue" : "Graded incorrect — continue")
    }

    func ratingRow(for word: SavedWord) -> some View {
        // The card face stays flat (content); only this rating bar goes glass.
        DSGlassGroup(spacing: DS.Spacing.lg) {
            HStack(spacing: DS.Spacing.lg) {
                actionButton(label: "Again", icon: "arrow.counterclockwise", color: DS.Color.danger,
                             shortcut: "1", shortcutLabel: "1") { recordRating(.again, word: word) }
                actionButton(label: "Hard", icon: "tortoise.fill", color: DS.Color.warning,
                             shortcut: "2", shortcutLabel: "2") { recordRating(.hard, word: word) }
                actionButton(label: "Good", icon: "checkmark.circle.fill", color: DS.Color.accent,
                             shortcut: "3", shortcutLabel: "3") { recordRating(.good, word: word) }
                actionButton(label: "Easy", icon: "checkmark.seal.fill", color: DS.Color.success,
                             shortcut: "4", shortcutLabel: "4") { recordRating(.easy, word: word) }
            }
        }
        .padding(.horizontal, DS.Spacing.xl)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }


    // MARK: - Action Button

    func actionButton(
        label: String,
        icon: String,
        color: Color,
        shortcut: KeyEquivalent,
        shortcutLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: DS.Spacing.xs) {
                Image(systemName: icon)
                    .font(DS.Typography.icon(22))
                Text(label)
                    .font(DS.Typography.caption.weight(.semibold))
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.md)
            // Neutral frosted chip; the colored icon + label carry the meaning
            // (calmer than three saturated tinted chips). Fallback keeps the
            // color wash on macOS 15.
            .dsGlassInteractive(
                cornerRadius: DS.Radius.md,
                fallback: AnyShapeStyle(color.opacity(0.10)),
                fallbackStroke: .none
            )
        }
        .buttonStyle(.plain)
        .keyboardShortcut(shortcut, modifiers: [])
        .help("\(label) - mark this card and continue (\(shortcutLabel))")
        .accessibilityHint("Marks the current card as \(label) and advances review")
    }

    // MARK: - Empty / All Mastered

    var emptyState: some View {
        DSEmptyState(
            icon: "star",
            title: "No saved words",
            message: "Save vocabulary from the reader to build your review queue."
        )
    }

    /// A book with nothing waiting (v16 S1, decision 3).
    var nothingWaitingInBook: some View {
        VStack(spacing: DS.Spacing.md) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(DS.Typography.icon(34, weight: .light))
                .foregroundStyle(DS.Color.success)
            Text("Nothing waiting in this book")
                .font(DS.Typography.headline)
            let all = store.pendingReviewCount
            if all > 0, let onStudyAll {
                Button(String(localized: "Study All (\(all))"), action: onStudyAll)
                    .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .padding(DS.Spacing.lg)
        .frame(maxWidth: .infinity)
    }

    var allMasteredState: some View {
        VStack(spacing: DS.Spacing.lg) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(DS.Typography.icon(40, weight: .light))
                .foregroundStyle(DS.Color.success)
            VStack(spacing: DS.Spacing.xs) {
                Text("All words mastered!")
                    .font(DS.Typography.headline)
                    .foregroundStyle(DS.Color.textPrimary)
                Text("Your review queue is clear. Include mastered words for extra practice.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
                    .multilineTextAlignment(.center)
            }
            Toggle("Include all saved words", isOn: $includeAll)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(DS.Typography.caption)
                .tint(DS.Color.accent)
            Spacer()
        }
        .padding(DS.Spacing.lg)
    }

    // MARK: - Mastery Badge

    func masteryBadge(_ level: MasteryLevel) -> some View {
        Label(level.label, systemImage: level.icon)
            .font(DS.Typography.caption2.weight(.semibold))
            .foregroundStyle(level.color)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.xxs + 1)
            .background(level.color.opacity(0.12))
            .clipShape(Capsule())
    }

    func sourceBadge(for word: SavedWord) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: "doc.text")
            Text(sourceText(for: word))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(DS.Typography.caption2)
        .foregroundStyle(DS.Color.textTertiary)
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xxs + 1)
        .background(DS.Color.surfaceInset)
        .clipShape(Capsule())
    }

    func sourceText(for word: SavedWord) -> String {
        if let pdfFilename = word.pdfFilename, let pageNumber = word.pageNumber {
            return "\(pdfFilename) · p.\(pageNumber)"
        }
        if let pdfFilename = word.pdfFilename {
            return pdfFilename
        }
        return "Saved vocabulary"
    }


}
