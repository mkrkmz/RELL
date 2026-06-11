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
    var onContinueReading: (() -> Void)? = nil
    var onOpenSavedWords: (() -> Void)? = nil

    @State private var queue: [SavedWord] = []
    @State private var currentIndex = 0
    @State private var isFlipped = false
    @State private var sessionAgain = 0
    @State private var sessionGood = 0
    @State private var sessionEasy = 0
    @State private var isFinished = false

    // Filter: due words only by default
    @State private var includeAll = false

    private var dueWords: [SavedWord] { store.dueWords() }

    private var wordsToQuiz: [SavedWord] {
        store.reviewQueue(includeAll: includeAll)
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
    }

    // MARK: - Start Screen

    private var startState: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: DS.Spacing.lg) {
                Image(systemName: "brain.filled.head.profile")
                    .font(.system(size: 38, weight: .light))
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

                Toggle("Include all saved words", isOn: $includeAll)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(DS.Typography.caption)
                    .tint(DS.Color.accent)
                    .help("Review every saved word instead of the due-first queue.")

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
                    Label(word.reviewStatus.label, systemImage: word.reviewStatus.icon)
                        .foregroundStyle(word.reviewStatus.color)
                }
                .font(DS.Typography.caption2.weight(.semibold))
                .foregroundStyle(DS.Color.textTertiary)
            }
            .padding(.horizontal, DS.Spacing.md)

            Spacer()

            // Card
            ZStack {
                // Back face
                cardFace(content: backContent(for: word), isFront: false)
                    .rotation3DEffect(.degrees(isFlipped ? 0 : -90), axis: (x: 0, y: 1, z: 0))
                    .opacity(isFlipped ? 1 : 0)

                // Front face
                cardFace(content: frontContent(for: word), isFront: true)
                    .rotation3DEffect(.degrees(isFlipped ? 90 : 0), axis: (x: 0, y: 1, z: 0))
                    .opacity(isFlipped ? 0 : 1)
            }
            .onTapGesture { flipCard() }

            // Hint
            if !isFlipped {
                Text("Tap to reveal")
                    .font(DS.Typography.caption2)
                    .foregroundStyle(DS.Color.textTertiary)
            }

            Spacer()

            // Action buttons (only shown after flip)
            if isFlipped {
                HStack(spacing: DS.Spacing.lg) {
                    actionButton(
                        label: "Again",
                        icon: "arrow.counterclockwise",
                        color: DS.Color.danger,
                        shortcut: "1",
                        shortcutLabel: "1"
                    ) { handleAgain(word: word) }

                    actionButton(
                        label: "Good",
                        icon: "checkmark.circle.fill",
                        color: DS.Color.accent,
                        shortcut: "2",
                        shortcutLabel: "2"
                    ) { handleGood(word: word) }

                    actionButton(
                        label: "Easy",
                        icon: "checkmark.seal.fill",
                        color: DS.Color.success,
                        shortcut: "3",
                        shortcutLabel: "3"
                    ) { handleKnown(word: word) }
                }
                .padding(.horizontal, DS.Spacing.xl)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.vertical, DS.Spacing.md)
        .animation(DS.Animation.springFast, value: isFlipped)
    }

    // MARK: - Card Faces

    private func cardFace(content: some View, isFront: Bool) -> some View {
        content
            .padding(DS.Spacing.lg)
            .frame(maxWidth: .infinity, minHeight: 160)
            .background(DS.Color.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .strokeBorder(DS.Color.separator.opacity(0.4), lineWidth: 0.8)
            )
            .dsShadow(DS.Shadow.card)
            .padding(.horizontal, DS.Spacing.md)
    }

    private func frontContent(for word: SavedWord) -> some View {
        VStack(spacing: DS.Spacing.sm) {
            Text("TERM")
                .font(DS.Typography.caption2.weight(.bold))
                .foregroundStyle(DS.Color.textTertiary)
            Text(word.term)
                .font(.system(size: 28, weight: .semibold, design: .default))
                .foregroundStyle(DS.Color.textPrimary)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.72)
            masteryBadge(word.masteryLevel)
            sourceBadge(for: word)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Review card front: \(word.term), mastery level \(word.masteryLevel.label), status \(word.reviewStatus.label)")
        .accessibilityHint("Tap to flip and see the definition")
    }

    private func backContent(for word: SavedWord) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("DEFINITION")
                .font(DS.Typography.caption2.weight(.bold))
                .foregroundStyle(DS.Color.textTertiary)
            Text(backText(for: word))
                .font(DS.Typography.body)
                .foregroundStyle(DS.Color.textPrimary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            sourceBadge(for: word)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func backText(for word: SavedWord) -> String {
        word.reviewDefinition
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
                    .font(.system(size: 22))
                Text(label)
                    .font(DS.Typography.caption.weight(.semibold))
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.md)
            .background(color.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(shortcut, modifiers: [])
        .help("\(label) - mark this card and continue (\(shortcutLabel))")
        .accessibilityHint("Marks the current card as \(label) and advances review")
    }

    // MARK: - Result Screen

    private var resultState: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: DS.Spacing.lg) {
                Image(systemName: sessionAgain == 0 ? "star.fill" : "checkmark.circle.fill")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(sessionAgain == 0 ? .yellow : DS.Color.success)

                VStack(spacing: DS.Spacing.xs) {
                    Text("Review Complete")
                        .font(DS.Typography.headline)
                        .foregroundStyle(DS.Color.textPrimary)
                    Text(resultSummaryText)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                        .multilineTextAlignment(.center)
                }

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
                .font(.system(size: 32, weight: .bold, design: .rounded))
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
                .font(.system(size: 40, weight: .light))
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
                .font(.system(size: 13, weight: .semibold))
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
        isFlipped = false
        sessionAgain = 0
        sessionGood = 0
        sessionEasy = 0
        isFinished = false
    }

    private func flipCard() {
        withAnimation(.easeInOut(duration: 0.25)) { isFlipped = true }
    }

    private func handleKnown(word: SavedWord) {
        sessionEasy += 1
        _ = store.applyReview(.easy, to: word)
        advance()
    }

    private func handleAgain(word: SavedWord) {
        sessionAgain += 1
        if let updated = store.applyReview(.again, to: word) {
            queue.append(updated)
        }
        advance()
    }

    private func handleGood(word: SavedWord) {
        sessionGood += 1
        _ = store.applyReview(.good, to: word)
        advance()
    }

    private func advance() {
        isFlipped = false
        let next = currentIndex + 1
        if next >= queue.count {
            isFinished = true
        } else {
            withAnimation(DS.Animation.springFast) { currentIndex = next }
        }
    }
}
