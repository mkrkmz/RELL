//
//  QuizSession.swift
//  Reader for Language Learner
//
//  One run through the review queue: which words, where we are, what the user
//  scored, and the answer state of the card on screen.
//
//  This used to live as a dozen flat `@State` properties on `QuizView`. Pulling
//  it out (Roadmap v10 Sprint 1) makes the progression logic unit-testable —
//  previously nothing here was covered — and gives each review mode one place
//  to reset its own per-card state instead of another branch in the view.
//

import Foundation

/// How a review card asks its question. Raw value is persisted (`quizMode`).
enum QuizMode: String, CaseIterable, Identifiable {
    case flashcard = "Flashcard"
    case multipleChoice = "Choice"
    case typed = "Type"
    /// Hear the word, then write it — the only mode that starts with audio.
    case listening = "Listen"

    var id: String { rawValue }

    /// Modes whose answer the app can check itself, rather than asking the
    /// user to judge their own recall.
    var isObjectivelyGraded: Bool {
        self == .typed || self == .listening
    }

    var icon: String {
        switch self {
        case .flashcard:      return "rectangle.on.rectangle"
        case .multipleChoice: return "list.bullet"
        case .typed:          return "keyboard"
        case .listening:      return "ear"
        }
    }

    var localizedTitle: String {
        switch self {
        case .flashcard:      return String(localized: "Flashcard")
        case .multipleChoice: return String(localized: "Choice")
        case .typed:          return String(localized: "Type")
        case .listening:      return String(localized: "Listen")
        }
    }
}

@MainActor
@Observable
final class QuizSession {

    // MARK: - Progression

    private(set) var queue: [SavedWord] = []
    private(set) var currentIndex = 0
    private(set) var isFinished = false

    // MARK: - Tallies

    private(set) var againCount = 0
    private(set) var goodCount = 0
    private(set) var easyCount = 0

    /// Answers the app graded itself (typed / listening) — separate from the
    /// Again/Good/Easy tallies, which are the user's own judgement.
    private(set) var gradedCount = 0
    private(set) var correctCount = 0

    // MARK: - Options

    /// Practice without touching the schedule: nothing reaches the store.
    var cram = false

    // MARK: - Per-card answer state

    var isFlipped = false
    var typedAnswer = ""
    var mcSelectedIndex: Int?
    private(set) var mcOptions: [String] = []
    var showAllBackSections = false

    /// Builds the multiple-choice options for a word. Injected rather than
    /// computed here: it needs the whole vocabulary (for distractors) and the
    /// word's saved definition — knowledge this type has no business holding.
    @ObservationIgnored var optionsBuilder: ((SavedWord) -> [String])?

    // MARK: - Derived

    var isActive: Bool { !queue.isEmpty }

    var currentWord: SavedWord? {
        queue.indices.contains(currentIndex) ? queue[currentIndex] : nil
    }

    /// 1-based position for display.
    var position: Int { currentIndex + 1 }
    var total: Int { queue.count }

    var isLastCard: Bool { currentIndex + 1 >= queue.count }

    /// Share of objectively-graded answers that were right, or nil when this
    /// session never asked a question the app could grade.
    var accuracy: Double? {
        gradedCount > 0 ? Double(correctCount) / Double(gradedCount) : nil
    }

    // MARK: - Lifecycle

    /// Starts a fresh run over `words` in random order.
    func begin(with words: [SavedWord], mode: QuizMode) {
        queue = words.shuffled()
        currentIndex = 0
        againCount = 0
        goodCount = 0
        easyCount = 0
        gradedCount = 0
        correctCount = 0
        isFinished = false
        prepareCard(mode: mode)
    }

    /// Clears per-card answer state and, for multiple choice, builds options.
    func prepareCard(mode: QuizMode) {
        isFlipped = false
        typedAnswer = ""
        mcSelectedIndex = nil
        mcOptions = []
        showAllBackSections = false
        guard let word = currentWord else { return }
        if mode == .multipleChoice {
            mcOptions = optionsBuilder?(word) ?? []
        }
    }

    func reveal() {
        isFlipped = true
    }

    func finish() {
        isFlipped = false
        isFinished = true
    }

    /// Returns to the card stack after the results screen ("Review More").
    func resume() {
        isFinished = false
    }

    // MARK: - Scoring

    /// Records the result of an answer the app checked itself.
    func recordObjectiveAnswer(correct: Bool) {
        gradedCount += 1
        if correct { correctCount += 1 }
    }

    /// Tallies a grade, schedules it through the store (unless cramming), and
    /// puts a lapsed word back on the end of the queue.
    func record(_ rating: ReviewRating, for word: SavedWord, in store: SavedWordsStore) {
        switch rating {
        case .again: againCount += 1
        // Hard is a successful recall, so it tallies with Good — matching how
        // the accuracy stats elsewhere treat anything that isn't `again`.
        case .hard, .good: goodCount += 1
        case .easy: easyCount += 1
        }

        if cram {
            if rating == .again { queue.append(word) }
        } else {
            let updated = store.applyReview(rating, to: word)
            if rating == .again, let updated { queue.append(updated) }
        }
    }

    /// Moves to the next card. Callers check `isLastCard` first when they want
    /// to animate the move but not the finish.
    func advance(mode: QuizMode) {
        let next = currentIndex + 1
        if next >= queue.count {
            finish()
        } else {
            currentIndex = next
            prepareCard(mode: mode)
        }
    }
}
