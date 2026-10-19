//
//  QuizView+Logic.swift
//  Reader for Language Learner
//
//  Queue logic and the multiple-choice options. Split out of QuizView.swift
//  (v19 S0), unchanged.
//

import SwiftUI

extension QuizView {

    // MARK: - Logic

    func beginQuiz() {
        // The session builds its own options; it can't reach the vocabulary.
        session.optionsBuilder = { buildOptions(for: $0) }
        session.modeResolver = { stageMode(for: $0) }
        // A round-based run only carries words that can actually be paired.
        session.begin(with: quizMode.isRoundBased ? matchableWords : wordsToQuiz, mode: quizMode)
    }

    func stageMode(for word: SavedWord) -> QuizMode {
        QuizMode.stageMode(for: word, canSpeak: SpeechManager.hasVoice(for: voiceLanguage(for: word)))
    }

    func flipCard() {
        withAnimation(DS.Animation.cardFlip) { session.reveal() }
    }

    func revealAnswer() {
        withAnimation(DS.Animation.standard) { session.reveal() }
        // Modes the app can grade itself record the objective result the moment
        // the answer is revealed — that's the only point where the typed answer
        // and the word are both still on hand.
        if cardMode.isObjectivelyGraded, let word = session.currentWord {
            session.recordObjectiveAnswer(
                correct: QuizMatching.matchesTerm(typed: session.typedAnswer, term: word.term)
            )
        }
    }

    func recordRating(_ rating: ReviewRating, word: SavedWord) {
        session.record(rating, for: word, in: store)
        advance()
    }

    func advance() {
        // Only the move between cards animates; finishing has the body's own
        // `.animation(_:value: session.isFinished)` transition.
        if session.isLastCard {
            session.finish()
        } else {
            withAnimation(DS.Animation.springFast) { session.advance(mode: quizMode) }
        }
    }

    // MARK: - Multiple Choice Options

    /// The correct term plus up to three distinct distractor terms drawn from
    /// other saved words. Returns empty when the word has no real definition
    /// to ask about, or when the vocabulary is too small for distractors —
    /// both signal a plain-reveal fallback.
    func buildOptions(for word: SavedWord) -> [String] {
        // The question shows the definition, so it must actually exist.
        guard word.usableDefinition != nil else { return [] }

        let candidates = store.words
            .filter { $0.id != word.id }
            .shuffled()
            .map(\.term)
        let distractors = QuizMatching.distractors(correct: word.term, candidates: candidates)

        guard !distractors.isEmpty else { return [] }
        return ([word.term] + distractors).shuffled()
    }
}
