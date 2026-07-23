//
//  QuizView.swift
//  Reader for Language Learner
//
//  Flashcard-style quiz over saved words.
//  Front: term. Back: definition (or first available LLM output).
//  "Know it" → mastery++, "Again" → stays in queue.
//

import SwiftUI

enum QuizMode: String, CaseIterable, Identifiable {
    case flashcard = "Flashcard"
    case multipleChoice = "Choice"
    case typed = "Type"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .flashcard:      return "rectangle.on.rectangle"
        case .multipleChoice: return "list.bullet"
        case .typed:          return "keyboard"
        }
    }

    var localizedTitle: String {
        switch self {
        case .flashcard:      return String(localized: "Flashcard")
        case .multipleChoice: return String(localized: "Choice")
        case .typed:          return String(localized: "Type")
        }
    }
}

struct QuizView: View {
    var store: SavedWordsStore
    var onContinueReading: (() -> Void)? = nil
    var onOpenSavedWords: (() -> Void)? = nil
    /// Set by modal hosts (the dashboard review sheet): shows a close button
    /// and binds Esc, so the quiz can be left mid-session. Window/sidebar
    /// hosts leave it nil — they already have their own exit.
    var onClose: (() -> Void)? = nil

    @State private var queue: [SavedWord] = []
    @State private var currentIndex = 0
    @State private var isFlipped = false
    @State private var sessionAgain = 0
    @State private var sessionGood = 0
    @State private var sessionEasy = 0
    @State private var isFinished = false

    // Filter: due words only by default
    @State private var includeAll = false
    @State private var selectedTag: String?

    // Modes
    @AppStorage("quizMode") private var quizModeRaw = QuizMode.flashcard.rawValue
    @State private var cram = false

    // Per-card answer state (multiple choice / typed)
    @State private var mcOptions: [String] = []
    @State private var mcSelectedIndex: Int?
    @State private var typedAnswer = ""
    /// Whether the card back is showing every saved module or just the summary.
    @State private var showAllBackSections = false

    /// Modules shown on the card back by default; the rest sit behind "Show more".
    private static let summaryModules: [ModuleType] = [.definitionEN, .meaningTR]

    private var quizMode: QuizMode {
        QuizMode(rawValue: quizModeRaw) ?? .flashcard
    }

    private var dueWords: [SavedWord] { store.dueWords() }

    private var wordsToQuiz: [SavedWord] {
        store.reviewQueue(includeAll: includeAll, tag: selectedTag)
    }

    private var isUsingFallbackQueue: Bool {
        !includeAll && dueWords.isEmpty && !store.reviewFallbackWords().isEmpty
    }

    var body: some View {
        Group {
            if store.words.isEmpty {
                emptyState
            } else if wordsToQuiz.isEmpty {
                allMasteredState
            } else if isFinished {
                resultState
            } else if queue.isEmpty {
                startState
            } else {
                quizCard
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(DS.Animation.standard, value: isFinished)
        .overlay(alignment: .topTrailing) { closeButton }
        // cancelAction alone doesn't fire in this sheet; cancelOperation:
        // via the responder chain is the reliable macOS Esc path.
        .onExitCommand { onClose?() }
    }

    /// Rendered only for modal hosts. `.cancelAction` is what makes Esc work:
    /// without a cancel-action button in the tree, Esc dies in the focusable
    /// flashcard's key-press chain and the sheet is inescapable mid-quiz.
    @ViewBuilder
    private var closeButton: some View {
        if let onClose {
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Color.textTertiary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close Review")
            .help("Close Review (Esc)")
            .padding(DS.Spacing.sm)
        }
    }

    // MARK: - Start Screen

    private var startState: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: DS.Spacing.lg) {
                Image(systemName: "brain.filled.head.profile")
                    .font(DS.Typography.icon(38, weight: .light))
                    .foregroundStyle(DS.Color.accent)

                VStack(spacing: DS.Spacing.xs) {
                    Text("Review Center")
                        .font(DS.Typography.headline)
                        .foregroundStyle(DS.Color.textPrimary)
                    Text(startSummaryText)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DS.Spacing.sm) {
                    reviewStat(icon: "clock.badge.exclamationmark", value: "\(dueWords.count)", label: "Due now", color: dueWords.isEmpty ? DS.Color.success : DS.Color.warning)
                    reviewStat(icon: "sparkles", value: "\(store.newCount)", label: "New", color: DS.Color.accent)
                    reviewStat(icon: "brain", value: "\(store.learningCount)", label: "Learning", color: DS.Color.warning)
                    reviewStat(icon: "checkmark.seal", value: "\(store.masteredCount)", label: "Mastered", color: DS.Color.success)
                    reviewStat(icon: "checkmark.circle", value: "\(store.reviewedTodayCount)", label: "Reviewed today", color: DS.Color.success)
                }

                Picker("Mode", selection: Binding(
                    get: { quizMode },
                    set: { quizModeRaw = $0.rawValue }
                )) {
                    ForEach(QuizMode.allCases) { mode in
                        Label(mode.localizedTitle, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("Flashcard reveal, pick the word for a definition, or type the missing word.")

                Toggle("Include all saved words", isOn: $includeAll)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(DS.Typography.caption)
                    .tint(DS.Color.accent)
                    .help("Review every saved word instead of the due-first queue.")

                Toggle("Cram — practice without changing the schedule", isOn: $cram)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(DS.Typography.caption)
                    .tint(DS.Color.warning)
                    .help("Drill cards without affecting spaced-repetition timing.")

                if !store.allTags.isEmpty {
                    Menu {
                        Button {
                            selectedTag = nil
                        } label: {
                            Label("All decks", systemImage: selectedTag == nil ? "checkmark" : "")
                        }
                        Divider()
                        ForEach(store.allTags, id: \.self) { tag in
                            Button {
                                selectedTag = tag
                            } label: {
                                Label(
                                    "\(tag) (\(store.tagCount(tag)))",
                                    systemImage: selectedTag?.lowercased() == tag.lowercased() ? "checkmark" : ""
                                )
                            }
                        }
                    } label: {
                        Label(selectedTag.map { "Deck: \($0)" } ?? "All decks", systemImage: "tag")
                            .font(DS.Typography.caption)
                    }
                    .menuStyle(.borderlessButton)
                    .controlSize(.small)
                    .fixedSize()
                    .help("Review only words in a deck (tag).")
                }

                Button {
                    beginQuiz()
                } label: {
                    Label("Start Review", systemImage: "play.fill")
                        .font(DS.Typography.callout.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
                .help("Start the current review queue")
            }
            .padding(DS.Spacing.lg)
        }
    }

    private var startSummaryText: String {
        if includeAll {
            return "\(wordsToQuiz.count) saved words are ready for an all-in review."
        }
        if !dueWords.isEmpty {
            return "\(dueWords.count) words are due now. Start here to keep the review queue moving."
        }
        if isUsingFallbackQueue {
            return "No words are due right now, so Review Center will practice new and learning words."
        }
        return "Your review queue is clear."
    }

    // MARK: - Quiz Card

    private var quizCard: some View {
        let word = queue[currentIndex]

        return VStack(spacing: DS.Spacing.lg) {
            VStack(spacing: DS.Spacing.xs) {
                ProgressView(value: Double(currentIndex + 1), total: Double(queue.count))
                    .tint(DS.Color.accent)
                HStack {
                    Text("Review \(currentIndex + 1) of \(queue.count)")
                    Spacer()
                    if cram {
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

            switch quizMode {
            case .flashcard:      flashcardBody(word)
            case .multipleChoice: multipleChoiceBody(word)
            case .typed:          typedBody(word)
            }

            Spacer()

            if isFlipped {
                ratingRow(for: word)
            }
        }
        .padding(.vertical, DS.Spacing.md)
        .animation(DS.Animation.springFast, value: isFlipped)
    }

    // MARK: - Flashcard Body

    @ViewBuilder
    private func flashcardBody(_ word: SavedWord) -> some View {
        ZStack {
            cardFace(content: backContent(for: word), isFront: false)
                .rotation3DEffect(.degrees(isFlipped ? 0 : -90), axis: (x: 0, y: 1, z: 0))
                .opacity(isFlipped ? 1 : 0)

            cardFace(content: frontContent(for: word), isFront: true)
                .rotation3DEffect(.degrees(isFlipped ? 90 : 0), axis: (x: 0, y: 1, z: 0))
                .opacity(isFlipped ? 0 : 1)
        }
        .onTapGesture { flipCard() }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space) { flipCard(); return .handled }
        .onKeyPress(.return) { flipCard(); return .handled }
        .onKeyPress(.escape) {
            guard let onClose else { return .ignored }
            onClose()
            return .handled
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(isFlipped ? "Card back" : "Card front")
        .accessibilityHint("Press space or return to flip")

        if !isFlipped {
            Text("Tap to reveal")
                .font(DS.Typography.caption2)
                .foregroundStyle(DS.Color.textTertiary)
        }
    }

    // MARK: - Multiple Choice Body (definition → term)

    @ViewBuilder
    private func multipleChoiceBody(_ word: SavedWord) -> some View {
        VStack(spacing: DS.Spacing.md) {
            if mcOptions.count < 2 {
                // No usable definition or not enough distractor terms —
                // fall back to a plain flashcard-style reveal.
                if isFlipped {
                    cardFace(content: revealContent(for: word), isFront: false)
                } else {
                    cardFace(content: frontContent(for: word), isFront: true)
                    Button("Reveal answer") { revealAnswer() }
                        .buttonStyle(.bordered)
                }
            } else {
                if isFlipped {
                    cardFace(content: revealContent(for: word), isFront: false)
                } else {
                    cardFace(content: choiceQuestionContent(for: word), isFront: true)
                }

                VStack(spacing: DS.Spacing.sm) {
                    ForEach(Array(mcOptions.enumerated()), id: \.offset) { index, option in
                        choiceRow(index: index, option: option, correct: word.term)
                    }
                }
                .padding(.horizontal, DS.Spacing.md)
            }
        }
    }

    /// Question card: the definition with the term masked out. The term,
    /// mastery badge, and source badge are all withheld until reveal — each
    /// one leaks the answer.
    private func choiceQuestionContent(for word: SavedWord) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("WHICH WORD FITS?")
                .font(DS.Typography.caption2.weight(.bold))
                .foregroundStyle(DS.Color.textTertiary)
            cardScroll(maxHeight: DS.Layout.cardBackHeightCompact) {
                Text(maskedDefinition(for: word))
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Color.textPrimary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func maskedDefinition(for word: SavedWord) -> String {
        QuizMatching.maskTerm(
            word.term,
            in: MarkdownUtils.sanitizeLLMOutput(word.reviewDefinition)
        )
    }

    private func choiceRow(index: Int, option: String, correct: String) -> some View {
        let isCorrect = option == correct
        let isSelected = mcSelectedIndex == index
        let tint: Color = {
            guard isFlipped else { return DS.Color.hairlineStrong }
            if isCorrect { return DS.Color.success }
            if isSelected { return DS.Color.danger }
            return DS.Color.hairlineStrong
        }()

        return Button {
            guard !isFlipped else { return }
            mcSelectedIndex = index
            revealAnswer()
        } label: {
            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                Image(systemName: isFlipped && (isCorrect || isSelected)
                      ? (isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                      : "circle")
                    .foregroundStyle(isFlipped && (isCorrect || isSelected) ? tint : DS.Color.textTertiary)
                Text(option)
                    .font(DS.Typography.callout.weight(.medium))
                    .foregroundStyle(DS.Color.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(DS.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((isFlipped && (isCorrect || isSelected) ? tint.opacity(0.10) : DS.Color.surfaceElevated))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .strokeBorder(tint, lineWidth: isFlipped && (isCorrect || isSelected) ? 1.2 : 0.6)
            )
        }
        .buttonStyle(.plain)
        .disabled(isFlipped)
        .accessibilityLabel(choiceAccessibilityLabel(option: option, isCorrect: isCorrect, isSelected: isSelected))
    }

    private func choiceAccessibilityLabel(option: String, isCorrect: Bool, isSelected: Bool) -> String {
        guard isFlipped else { return option }
        if isCorrect { return String(localized: "\(option), correct answer") }
        if isSelected { return String(localized: "\(option), your answer, incorrect") }
        return option
    }

    // MARK: - Typed Recall Body (cloze → type the word)

    @ViewBuilder
    private func typedBody(_ word: SavedWord) -> some View {
        let hasQuestion = clozeSentence(for: word) != nil || usableDefinition(for: word) != nil

        VStack(spacing: DS.Spacing.md) {
            if isFlipped {
                cardFace(content: revealContent(for: word), isFront: false)
            } else if hasQuestion {
                cardFace(content: typedQuestionContent(for: word), isFront: true)
            } else {
                cardFace(content: frontContent(for: word), isFront: true)
            }

            if !isFlipped {
                if hasQuestion {
                    VStack(spacing: DS.Spacing.sm) {
                        TextField("Type the word…", text: $typedAnswer)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { if !typedAnswer.trimmingCharacters(in: .whitespaces).isEmpty { revealAnswer() } }
                        Button("Check") { revealAnswer() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                            .disabled(typedAnswer.trimmingCharacters(in: .whitespaces).isEmpty)
                            .keyboardShortcut(.return, modifiers: [.command])
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                } else {
                    // Nothing to build a question from — plain reveal.
                    Button("Reveal answer") { revealAnswer() }
                        .buttonStyle(.bordered)
                }
            } else if hasQuestion {
                typedResultView(word)
            }
        }
    }

    /// Question card: the saved sentence as a cloze (term blanked out) plus
    /// the masked definition as a secondary hint.
    private func typedQuestionContent(for word: SavedWord) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text(clozeSentence(for: word) != nil ? "TYPE THE MISSING WORD" : "TYPE THE WORD")
                .font(DS.Typography.caption2.weight(.bold))
                .foregroundStyle(DS.Color.textTertiary)

            cardScroll(maxHeight: DS.Layout.cardBackHeightCompact) {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    if let cloze = clozeSentence(for: word) {
                        Text("“\(cloze)”")
                            .font(DS.Typography.body)
                            .italic()
                            .foregroundStyle(DS.Color.textPrimary)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let definition = usableDefinition(for: word) {
                        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                            Text("HINT")
                                .font(DS.Typography.caption2.weight(.bold))
                                .foregroundStyle(DS.Color.textTertiary)
                            Text(QuizMatching.maskTerm(word.term, in: definition))
                                .font(DS.Typography.callout)
                                .foregroundStyle(DS.Color.textSecondary)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Objective ✓/✗ result shown under the reveal card.
    private func typedResultView(_ word: SavedWord) -> some View {
        let isCorrect = QuizMatching.matchesTerm(typed: typedAnswer, term: word.term)
        let tint = isCorrect ? DS.Color.success : DS.Color.danger
        let trimmedAnswer = typedAnswer.trimmingCharacters(in: .whitespaces)

        return HStack(spacing: DS.Spacing.sm) {
            Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(tint)
            Text(isCorrect ? "Correct!" : "Not quite")
                .font(DS.Typography.caption.weight(.semibold))
                .foregroundStyle(tint)
            if !isCorrect, !trimmedAnswer.isEmpty {
                Text("— you wrote “\(trimmedAnswer)”")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textSecondary)
                    .italic()
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Spacing.md)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        .padding(.horizontal, DS.Spacing.md)
    }

    /// The saved sentence with the term masked, or nil when the sentence is
    /// missing or doesn't contain the term (no blank → not a cloze).
    private func clozeSentence(for word: SavedWord) -> String? {
        let sentence = word.sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty else { return nil }
        let masked = QuizMatching.maskTerm(word.term, in: sentence)
        return masked == sentence ? nil : masked
    }

    /// A real saved definition (not the placeholder fallback), sanitized.
    private func usableDefinition(for word: SavedWord) -> String? {
        let priority = [ModuleType.definitionEN.rawValue, ModuleType.meaningTR.rawValue]
        for key in priority {
            if let text = word.llmOutputs[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                return MarkdownUtils.sanitizeLLMOutput(text)
            }
        }
        return nil
    }

    // MARK: - Rating Row

    private func ratingRow(for word: SavedWord) -> some View {
        // The card face stays flat (content); only this rating bar goes glass.
        DSGlassGroup(spacing: DS.Spacing.lg) {
            HStack(spacing: DS.Spacing.lg) {
                actionButton(label: "Again", icon: "arrow.counterclockwise", color: DS.Color.danger,
                             shortcut: "1", shortcutLabel: "1") { recordRating(.again, word: word) }
                actionButton(label: "Good", icon: "checkmark.circle.fill", color: DS.Color.accent,
                             shortcut: "2", shortcutLabel: "2") { recordRating(.good, word: word) }
                actionButton(label: "Easy", icon: "checkmark.seal.fill", color: DS.Color.success,
                             shortcut: "3", shortcutLabel: "3") { recordRating(.easy, word: word) }
            }
        }
        .padding(.horizontal, DS.Spacing.xl)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Card Faces

    private func cardFace(content: some View, isFront: Bool) -> some View {
        content
            .padding(DS.Spacing.lg)
            .frame(maxWidth: .infinity, minHeight: DS.Layout.cardFrontMinHeight)
            .dsCard(padding: nil, radius: DS.Radius.lg, stroke: .hairlineStrong)
            .dsShadow(DS.Shadow.card)
            .padding(.horizontal, DS.Spacing.md)
    }

    private func frontContent(for word: SavedWord) -> some View {
        VStack(spacing: DS.Spacing.sm) {
            Text("TERM")
                .font(DS.Typography.caption2.weight(.bold))
                .foregroundStyle(DS.Color.textTertiary)
            HStack(spacing: DS.Spacing.sm) {
                Text(word.term)
                    .font(DS.Typography.wordDisplayLarge)
                    .foregroundStyle(DS.Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.72)
                SpeakButton(text: word.term, size: 15)
            }
            masteryBadge(word.masteryLevel)
            sourceBadge(for: word)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Review card front: \(word.term), mastery level \(word.masteryLevel.label), status \(word.reviewStatus.label)")
        .accessibilityHint("Tap to flip and see the definition")
    }

    /// Flashcard back: every saved module, summary-first with "Show more".
    private func backContent(for word: SavedWord) -> some View {
        backSections(for: word, maxHeight: DS.Layout.cardBackHeightExpanded)
    }

    /// Reveal card for choice/typed modes — the question hid the term, so the
    /// reveal leads with it before the saved content.
    private func revealContent(for word: SavedWord) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                Text(word.term)
                    .font(DS.Typography.wordDisplay)
                    .foregroundStyle(DS.Color.textPrimary)
                    .minimumScaleFactor(0.72)
                SpeakButton(text: word.term, size: 13)
                Spacer(minLength: 0)
                masteryBadge(word.masteryLevel)
            }
            Divider()
            backSections(for: word, maxHeight: DS.Layout.cardBackHeightCompact)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Scrollable, labeled sections for all saved module outputs.
    /// Definition + native meaning show by default; the rest expand on demand.
    private func backSections(for word: SavedWord, maxHeight: CGFloat) -> some View {
        let saved = savedModules(for: word)
        let summary = saved.filter { Self.summaryModules.contains($0) }
        // If neither summary module was saved, promote the first output so the
        // back is never just a "Show more" button.
        let visible = summary.isEmpty ? Array(saved.prefix(1)) : summary
        let hidden = saved.filter { !visible.contains($0) }

        return cardScroll(maxHeight: maxHeight) {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                if saved.isEmpty {
                    // No LLM outputs at all — fall back to sentence/placeholder.
                    Text(word.reviewDefinition)
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Color.textPrimary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(visible) { module in
                        moduleSection(module, word: word)
                    }

                    if !hidden.isEmpty {
                        if showAllBackSections {
                            ForEach(hidden) { module in
                                moduleSection(module, word: word)
                            }
                        } else {
                            Button {
                                withAnimation(DS.Animation.standard) { showAllBackSections = true }
                            } label: {
                                Label("Show more (\(hidden.count))", systemImage: "chevron.down")
                                    .font(DS.Typography.caption2.weight(.semibold))
                                    .foregroundStyle(DS.Color.accent)
                            }
                            .buttonStyle(.plain)
                            .help("Show the other saved modules for this word")
                        }
                    }
                }

                sourceBadge(for: word)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// One labeled section on the card back (module dot + title + output).
    private func moduleSection(_ module: ModuleType, word: SavedWord) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            HStack(spacing: DS.Spacing.xs) {
                Circle()
                    .fill(module.accentColor)
                    .frame(width: 5, height: 5)
                Text(module.title.uppercased())
                    .font(DS.Typography.caption2.weight(.bold))
                    .foregroundStyle(DS.Color.textTertiary)
            }
            Text(MarkdownUtils.sanitizeLLMOutput(word.llmOutputs[module.rawValue] ?? ""))
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Color.textPrimary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Modules with a non-empty saved output, in canonical module order.
    private func savedModules(for word: SavedWord) -> [ModuleType] {
        ModuleType.allCases.filter {
            !(word.llmOutputs[$0.rawValue] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Bounded scroll container used by card bodies so long content scrolls
    /// inside the card instead of overflowing the sidebar.
    private func cardScroll<Content: View>(
        maxHeight: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: maxHeight)
    }

    // MARK: - Action Button

    private func actionButton(
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

    // MARK: - Review Streak Banner

    /// Flame + current streak, plus a snowflake count when freezes are banked.
    /// Earned freezes auto-bridge a single missed day (see ReviewStreak).
    @ViewBuilder
    private var reviewStreakBanner: some View {
        let streak = store.reviewStreak()
        if streak.current > 0 {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(DS.Color.warning)
                Text("\(streak.current)-day streak")
                    .font(DS.Typography.subhead.weight(.semibold))
                    .foregroundStyle(DS.Color.textPrimary)

                if streak.freezesRemaining > 0 {
                    Divider().frame(height: 12)
                    HStack(spacing: 2) {
                        Image(systemName: "snowflake")
                            .foregroundStyle(DS.Color.accent)
                        Text("\(streak.freezesRemaining)")
                            .font(DS.Typography.caption.weight(.semibold))
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                    .help("Streak freezes — each automatically covers one missed day")
                }
            }
            .font(DS.Typography.caption)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .dsGlassCapsule(fallbackShadow: nil)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                streak.freezesRemaining > 0
                    ? "\(streak.current) day review streak, \(streak.freezesRemaining) freezes banked"
                    : "\(streak.current) day review streak"
            )
        }
    }

    // MARK: - Result Screen

    private var resultState: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: DS.Spacing.lg) {
                Image(systemName: sessionAgain == 0 ? "star.fill" : "checkmark.circle.fill")
                    .font(DS.Typography.icon(46, weight: .light))
                    .foregroundStyle(sessionAgain == 0 ? DS.Color.star : DS.Color.success)

                VStack(spacing: DS.Spacing.xs) {
                    Text("Review Complete")
                        .font(DS.Typography.headline)
                        .foregroundStyle(DS.Color.textPrimary)
                    Text(resultSummaryText)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                        .multilineTextAlignment(.center)
                }

                reviewStreakBanner

                HStack(spacing: DS.Spacing.lg) {
                    resultStat(value: "\(sessionGood)", label: "Good", color: DS.Color.accent)
                    resultStat(value: "\(sessionEasy)", label: "Easy", color: DS.Color.success)
                    resultStat(value: "\(sessionAgain)", label: "Again", color: DS.Color.danger)
                }

                VStack(spacing: DS.Spacing.sm) {
                    Button {
                        isFinished = false
                        beginQuiz()
                    } label: {
                        Label(store.pendingReviewCount > 0 ? "Review More" : "Practice Again", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(wordsToQuiz.isEmpty)

                    if let onContinueReading {
                        Button(action: onContinueReading) {
                            Label("Continue Reading", systemImage: "book.pages")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }

                    if let onOpenSavedWords {
                        Button(action: onOpenSavedWords) {
                            Label("Open Saved Words", systemImage: "star")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }
                }
                .font(DS.Typography.caption.weight(.semibold))

                Text("\(store.pendingReviewCount) words still due")
                    .font(DS.Typography.caption2)
                    .foregroundStyle(DS.Color.textTertiary)
            }
            .padding(DS.Spacing.lg)
        }
    }

    private var resultSummaryText: String {
        if store.pendingReviewCount > 0 {
            return "Nice pass. There are still due words waiting in the queue."
        }
        if sessionAgain > 0 {
            return "Good work. Words marked Again are scheduled back into review soon."
        }
        return "Clean session. Your due queue is clear for now."
    }

    private func resultStat(value: String, label: String, color: Color) -> some View {
        VStack(spacing: DS.Spacing.xxs) {
            Text(value)
                .font(DS.Typography.statNumber(32))
                .foregroundStyle(color)
            Text(label)
                .font(DS.Typography.caption2)
                .foregroundStyle(DS.Color.textTertiary)
        }
    }

    // MARK: - Empty / All Mastered

    private var emptyState: some View {
        DSEmptyState(
            icon: "star",
            title: "No saved words",
            message: "Save vocabulary from the reader to build your review queue."
        )
    }

    private var allMasteredState: some View {
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

    private func masteryBadge(_ level: MasteryLevel) -> some View {
        Label(level.label, systemImage: level.icon)
            .font(DS.Typography.caption2.weight(.semibold))
            .foregroundStyle(level.color)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.xxs + 1)
            .background(level.color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func sourceBadge(for word: SavedWord) -> some View {
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

    private func sourceText(for word: SavedWord) -> String {
        if let pdfFilename = word.pdfFilename, let pageNumber = word.pageNumber {
            return "\(pdfFilename) · p.\(pageNumber)"
        }
        if let pdfFilename = word.pdfFilename {
            return pdfFilename
        }
        return "Saved vocabulary"
    }

    private func reviewStat(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Image(systemName: icon)
                .font(DS.Typography.icon(13, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(DS.Typography.headline)
                .foregroundStyle(DS.Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(DS.Typography.caption2)
                .foregroundStyle(DS.Color.textTertiary)
                .lineLimit(1)
        }
        .padding(DS.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
    }

    // MARK: - Logic

    private func beginQuiz() {
        queue = wordsToQuiz.shuffled()
        currentIndex = 0
        sessionAgain = 0
        sessionGood = 0
        sessionEasy = 0
        isFinished = false
        prepareCard()
    }

    /// Resets per-card answer state and, for multiple choice, builds options.
    private func prepareCard() {
        isFlipped = false
        typedAnswer = ""
        mcSelectedIndex = nil
        mcOptions = []
        showAllBackSections = false
        guard currentIndex < queue.count else { return }
        if quizMode == .multipleChoice {
            mcOptions = buildOptions(for: queue[currentIndex])
        }
    }

    private func flipCard() {
        withAnimation(DS.Animation.cardFlip) { isFlipped = true }
    }

    private func revealAnswer() {
        withAnimation(DS.Animation.standard) { isFlipped = true }
    }

    /// Records a grade. In cram mode scheduling is left untouched (no
    /// `applyReview`); only the session tally and requeue-on-Again apply.
    private func recordRating(_ rating: ReviewRating, word: SavedWord) {
        switch rating {
        case .again: sessionAgain += 1
        case .good:  sessionGood += 1
        case .easy:  sessionEasy += 1
        }

        if cram {
            if rating == .again { queue.append(word) }
        } else {
            let updated = store.applyReview(rating, to: word)
            if rating == .again, let updated { queue.append(updated) }
        }
        advance()
    }

    private func advance() {
        let next = currentIndex + 1
        if next >= queue.count {
            isFlipped = false
            isFinished = true
        } else {
            currentIndex = next
            withAnimation(DS.Animation.springFast) { prepareCard() }
        }
    }

    // MARK: - Multiple Choice Options

    /// The correct term plus up to three distinct distractor terms drawn from
    /// other saved words. Returns empty when the word has no real definition
    /// to ask about, or when the vocabulary is too small for distractors —
    /// both signal a plain-reveal fallback.
    private func buildOptions(for word: SavedWord) -> [String] {
        // The question shows the definition, so it must actually exist.
        guard usableDefinition(for: word) != nil else { return [] }

        let candidates = store.words
            .filter { $0.id != word.id }
            .shuffled()
            .map(\.term)
        let distractors = QuizMatching.distractors(correct: word.term, candidates: candidates)

        guard !distractors.isEmpty else { return [] }
        return ([word.term] + distractors).shuffled()
    }
}
