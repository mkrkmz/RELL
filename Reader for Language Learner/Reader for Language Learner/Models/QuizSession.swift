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
    /// A grid of terms and definitions to pair up — several words at once,
    /// rather than one card at a time.
    case matching = "Match"

    var id: String { rawValue }

    /// Modes whose answer the app can check itself, rather than asking the
    /// user to judge their own recall.
    var isObjectivelyGraded: Bool {
        self == .typed || self == .listening
    }

    /// Whether an answer in this mode reaches the scheduler.
    ///
    /// Matching doesn't. Recognising a word among five on a grid isn't
    /// recalling it, and writing `good` to FSRS for that would stretch
    /// intervals the answer didn't earn — so the game practices without
    /// touching the schedule, the way cram does.
    var affectsSchedule: Bool { self != .matching }

    /// Whether the mode asks about several words at once.
    var isRoundBased: Bool { self == .matching }

    var icon: String {
        switch self {
        case .flashcard:      return "rectangle.on.rectangle"
        case .multipleChoice: return "list.bullet"
        case .typed:          return "keyboard"
        case .listening:      return "ear"
        case .matching:       return "square.grid.2x2"
        }
    }

    var localizedTitle: String {
        switch self {
        case .flashcard:      return String(localized: "Flashcard")
        case .multipleChoice: return String(localized: "Choice")
        case .typed:          return String(localized: "Type")
        case .listening:      return String(localized: "Listen")
        case .matching:       return String(localized: "Match")
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

    // MARK: - Answers (v15 S2)

    /// One graded answer, for the study room's summary.
    struct Answer: Equatable {
        let wordID: UUID
        let term: String
        let rating: ReviewRating
        let nextReviewAt: Date?
    }

    private(set) var answers: [Answer] = []
    private(set) var startedAt: Date?

    /// What undoing the last grade puts back.
    private struct Step {
        let before: SavedWord
        let index: Int
        let requeued: Bool
        let tallies: Tallies
        let answerCount: Int
    }

    private struct Tallies {
        var again = 0, good = 0, easy = 0, graded = 0, correct = 0
    }

    @ObservationIgnored private var history: [Step] = []
    /// The tallies as the card on screen was shown — an undo restores them,
    /// including an objective grade recorded at reveal.
    @ObservationIgnored private var talliesAtCardStart = Tallies()

    var canUndo: Bool { !history.isEmpty }

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

    /// Starts a fresh run over `words` — in random order, or as given (the
    /// study room orders its own queue).
    func begin(with words: [SavedWord], mode: QuizMode, shuffle: Bool = true) {
        queue = shuffle ? words.shuffled() : words
        currentIndex = 0
        againCount = 0
        goodCount = 0
        easyCount = 0
        gradedCount = 0
        correctCount = 0
        isFinished = false
        answers = []
        history = []
        startedAt = Date()
        prepareCard(mode: mode)
    }

    /// Clears per-card answer state and, for multiple choice, builds options.
    func prepareCard(mode: QuizMode) {
        isFlipped = false
        typedAnswer = ""
        mcSelectedIndex = nil
        mcOptions = []
        showAllBackSections = false
        talliesAtCardStart = currentTallies
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

    /// Back to the setup screen: no queue, nothing finished.
    func reset() {
        queue = []
        currentIndex = 0
        isFinished = false
        answers = []
        history = []
        startedAt = nil
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
        let before = store.word(withID: word.id) ?? word
        let queueCount = queue.count
        let tallies = talliesAtCardStart
        let answerCount = answers.count
        defer {
            history.append(Step(before: before, index: currentIndex, requeued: queue.count > queueCount,
                                tallies: tallies, answerCount: answerCount))
        }
        switch rating {
        case .again: againCount += 1
        // Hard is a successful recall, so it tallies with Good — matching how
        // the accuracy stats elsewhere treat anything that isn't `again`.
        case .hard, .good: goodCount += 1
        case .easy: easyCount += 1
        }

        if cram {
            if rating == .again { queue.append(word) }
            answers.append(Answer(wordID: word.id, term: word.term, rating: rating, nextReviewAt: nil))
        } else {
            let updated = store.applyReview(rating, to: word)
            if rating == .again, let updated { queue.append(updated) }
            answers.append(Answer(wordID: word.id, term: word.term, rating: rating, nextReviewAt: updated?.nextReviewAt))
        }
    }

    /// Takes back the last grade: the word's schedule as it was, the
    /// tallies, and the card back on screen (v15 S2, ←). False when there's
    /// nothing to undo.
    @discardableResult
    func undoLast(in store: SavedWordsStore, mode: QuizMode) -> Bool {
        guard let step = history.popLast() else { return false }
        // The copy put back for an "Again" — found by id, since a skip may
        // have moved other cards behind it.
        if step.requeued, let copy = queue.lastIndex(where: { $0.id == step.before.id }), copy > step.index {
            queue.remove(at: copy)
        }
        if !cram { store.update(step.before) }
        if queue.indices.contains(step.index) { queue[step.index] = step.before }
        againCount = step.tallies.again
        goodCount = step.tallies.good
        easyCount = step.tallies.easy
        gradedCount = step.tallies.graded
        correctCount = step.tallies.correct
        answers.removeLast(answers.count - step.answerCount)
        currentIndex = step.index
        isFinished = false
        prepareCard(mode: mode)
        return true
    }

    /// Puts the card on screen at the end of the queue (→). Nothing happens
    /// on the last card.
    func skipCurrent(mode: QuizMode) {
        guard !isLastCard, queue.indices.contains(currentIndex) else { return }
        let word = queue.remove(at: currentIndex)
        queue.append(word)
        prepareCard(mode: mode)
    }

    private var currentTallies: Tallies {
        Tallies(again: againCount, good: goodCount, easy: easyCount, graded: gradedCount, correct: correctCount)
    }

    /// Moves past a whole grid at once — the matching game answers several
    /// words in one round, and none of them reach the store.
    ///
    /// A run also ends when too few words remain to fill another grid:
    /// `minimumRemaining` is the smallest grid worth playing, and a leftover
    /// smaller than that would otherwise leave a dead round on screen with no
    /// way forward.
    func advanceRound(of count: Int, minimumRemaining: Int = 1, mode: QuizMode) {
        let next = currentIndex + max(1, count)
        if next >= queue.count || queue.count - next < max(1, minimumRemaining) {
            finish()
        } else {
            currentIndex = next
            prepareCard(mode: mode)
        }
    }

    /// How many grids this queue actually plays: the full ones, plus a final
    /// short one only when it still reaches `minimum`.
    func playableRounds(of size: Int, minimum: Int) -> Int {
        let step = max(1, size)
        let full = queue.count / step
        let remainder = queue.count % step
        return max(1, full + (remainder >= max(1, minimum) ? 1 : 0))
    }

    /// Where this round sits in the run, for a round-based mode's header.
    func roundPosition(of size: Int) -> Int {
        currentIndex / max(1, size) + 1
    }

    func roundTotal(of size: Int) -> Int {
        guard !queue.isEmpty else { return 1 }
        let step = max(1, size)
        return (queue.count + step - 1) / step
    }

    /// The next `count` words still ahead in the queue — one grid's worth.
    func upcoming(_ count: Int) -> [SavedWord] {
        guard currentIndex < queue.count else { return [] }
        return Array(queue[currentIndex..<min(currentIndex + count, queue.count)])
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
