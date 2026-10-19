//
//  QuizView+Matching.swift
//  Reader for Language Learner
//
//  The matching round. Split out of QuizView.swift (v19 S0), unchanged.
//

import SwiftUI

extension QuizView {

    // MARK: - Matching Round

    @ViewBuilder
    var matchingRound: some View {
        let words = session.upcoming(MatchingRound.defaultPairs)
        QuizMatchingBody(
            words: words,
            roundPosition: session.roundPosition(of: MatchingRound.defaultPairs),
            roundTotal: session.playableRounds(
                of: MatchingRound.defaultPairs,
                minimum: MatchingRound.minimumPairs
            ),
            isCram: session.cram,
            onAttempt: { session.recordObjectiveAnswer(correct: $0) },
            onRoundComplete: {
                session.advanceRound(
                    of: words.count,
                    minimumRemaining: MatchingRound.minimumPairs,
                    mode: quizMode
                )
            }
        )
    }

    var canSpeakVocabulary: Bool {
        if SpeechManager.hasVoice(for: Language.storedTarget) { return true }
        let saved = Set(store.words.compactMap { $0.language.flatMap(Language.init(rawValue:)) })
        return saved.contains(where: SpeechManager.hasVoice(for:))
    }

    var dueWords: [SavedWord] { inScope(store.dueWords()) }

    var wordsToQuiz: [SavedWord] {
        inScope(store.reviewQueue(includeAll: includeAll, tag: selectedTag))
    }

    var isUsingFallbackQueue: Bool {
        !includeAll && dueWords.isEmpty && !inScope(store.reviewFallbackWords()).isEmpty
    }

    func inScope(_ words: [SavedWord]) -> [SavedWord] {
        guard let scopeIDs else { return words }
        return words.filter { scopeIDs.contains($0.id) }
    }

    var body: some View {
        Group {
            if store.words.isEmpty {
                emptyState
            } else if style == .room {
                roomContent
            } else if wordsToQuiz.isEmpty && scopeIDs != nil {
                nothingWaitingInBook
            } else if wordsToQuiz.isEmpty {
                allMasteredState
            } else if session.isFinished {
                QuizResultView(
                    session: session,
                    store: store,
                    mode: quizMode,
                    canReviewMore: !wordsToQuiz.isEmpty,
                    onReviewMore: {
                        session.resume()
                        beginQuiz()
                    },
                    onContinueReading: onContinueReading,
                    onOpenSavedWords: onOpenSavedWords
                )
            } else if !session.isActive {
                QuizStartView(
                    store: store,
                    session: session,
                    wordsToQuiz: wordsToQuiz,
                    dueWords: dueWords,
                    isUsingFallbackQueue: isUsingFallbackQueue,
                    availableModes: availableModes,
                    quizMode: Binding(
                        get: { quizMode },
                        set: { quizModeRaw = $0.rawValue }
                    ),
                    includeAll: $includeAll,
                    selectedTag: $selectedTag,
                    typedAutoGrade: $typedAutoGrade,
                    onStart: beginQuiz
                )
            } else if quizMode.isRoundBased {
                matchingRound
            } else {
                quizCard
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(DS.Animation.standard, value: session.isFinished)
        .overlay(alignment: .topTrailing) { if style == .sidebar { closeButton } }
        // cancelAction alone doesn't fire in this sheet; cancelOperation:
        // via the responder chain is the reliable macOS Esc path.
        .onExitCommand { handleEscape() }
    }

    /// Rendered only for modal hosts. `.cancelAction` is what makes Esc work:
    /// without a cancel-action button in the tree, Esc dies in the focusable
    /// flashcard's key-press chain and the sheet is inescapable mid-quiz.
    @ViewBuilder
    var closeButton: some View {
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
}
