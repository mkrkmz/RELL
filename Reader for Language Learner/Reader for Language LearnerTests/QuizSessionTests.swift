//
//  QuizSessionTests.swift
//  Reader for Language LearnerTests
//
//  Review-session progression (Roadmap v10 Sprint 1). This logic lived as flat
//  `@State` on QuizView and was therefore untestable; these cover the queue
//  walk, the cram contract, lapse requeueing and objective accuracy.
//
//  Methods are `async` per the CI-safe convention — synchronous @MainActor test
//  methods that drive the stores deadlocked the core-constrained runner.
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class QuizSessionTests: XCTestCase {
    private static var retainedStores: [SavedWordsStore] = []
    private static var retainedSessions: [QuizSession] = []

    /// Retained for the class lifetime so the session isn't deallocated inside
    /// XCTest's post-scope memory checker. That path — an `@Observable`
    /// `@MainActor` object released as the test scope ends — aborts inside
    /// `swift_task_deinitOnExecutor` on the CI toolchain, which killed the
    /// v1.38.0 release run. `QuickLookupServiceTests` avoids the same path for
    /// the same reason; the app keeps one session alive per review window
    /// anyway.
    private func makeSession() -> QuizSession {
        let session = QuizSession()
        Self.retainedSessions.append(session)
        return session
    }

    // MARK: - Progression

    func testBeginLoadsEveryWordAndStartsAtTheFirstCard() async throws {
        let session = makeSession()
        session.begin(with: [word("one"), word("two"), word("three")], mode: .flashcard)

        XCTAssertEqual(session.total, 3)
        XCTAssertEqual(session.position, 1)
        XCTAssertFalse(session.isFinished)
        XCTAssertTrue(session.isActive)
        XCTAssertNotNil(session.currentWord)
    }

    func testAdvanceWalksToTheEndThenFinishes() async throws {
        let session = makeSession()
        session.begin(with: [word("one"), word("two")], mode: .flashcard)

        XCTAssertFalse(session.isLastCard)
        session.advance(mode: .flashcard)
        XCTAssertEqual(session.position, 2)
        XCTAssertTrue(session.isLastCard)

        session.advance(mode: .flashcard)
        XCTAssertTrue(session.isFinished)
    }

    func testBeginResetsEverythingFromAPreviousRun() async throws {
        let store = makeStore()
        let session = makeSession()
        let first = word("one")
        store.add(first)
        session.begin(with: [first], mode: .flashcard)
        session.record(.again, for: first, in: store)
        session.recordObjectiveAnswer(correct: false)
        session.finish()

        session.begin(with: [word("fresh")], mode: .flashcard)

        XCTAssertEqual(session.againCount, 0)
        XCTAssertEqual(session.goodCount, 0)
        XCTAssertEqual(session.easyCount, 0)
        XCTAssertNil(session.accuracy)
        XCTAssertFalse(session.isFinished)
        XCTAssertEqual(session.position, 1)
    }

    func testResumeReturnsToTheCards() async throws {
        let session = makeSession()
        session.begin(with: [word("one")], mode: .flashcard)
        session.finish()
        XCTAssertTrue(session.isFinished)

        session.resume()
        XCTAssertFalse(session.isFinished)
    }

    // MARK: - Per-card state

    func testPreparingACardClearsThePreviousAnswer() async throws {
        let session = makeSession()
        session.begin(with: [word("one"), word("two")], mode: .flashcard)
        session.typedAnswer = "guess"
        session.mcSelectedIndex = 2
        session.showAllBackSections = true
        session.reveal()

        session.advance(mode: .flashcard)

        XCTAssertEqual(session.typedAnswer, "")
        XCTAssertNil(session.mcSelectedIndex)
        XCTAssertFalse(session.showAllBackSections)
        XCTAssertFalse(session.isFlipped)
    }

    func testMultipleChoiceOptionsComeFromTheInjectedBuilder() async throws {
        let session = makeSession()
        session.optionsBuilder = { ["\($0.term)-a", "\($0.term)-b"] }

        session.begin(with: [word("orbit")], mode: .multipleChoice)
        XCTAssertEqual(session.mcOptions, ["orbit-a", "orbit-b"])

        // Other modes never pay for option building.
        session.begin(with: [word("orbit")], mode: .flashcard)
        XCTAssertTrue(session.mcOptions.isEmpty)
    }

    // MARK: - Scoring

    func testGradesTallyWithHardCountingAsASuccess() async throws {
        let store = makeStore()
        let session = makeSession()
        let a = word("a"), b = word("b"), c = word("c"), d = word("d")
        [a, b, c, d].forEach { store.add($0) }
        session.begin(with: [a, b, c, d], mode: .flashcard)

        session.record(.again, for: a, in: store)
        session.record(.hard, for: b, in: store)
        session.record(.good, for: c, in: store)
        session.record(.easy, for: d, in: store)

        XCTAssertEqual(session.againCount, 1)
        XCTAssertEqual(session.goodCount, 2, "hard tallies with good — both are successful recalls")
        XCTAssertEqual(session.easyCount, 1)
    }

    func testALapseGoesBackOnTheQueue() async throws {
        let store = makeStore()
        let session = makeSession()
        let missed = word("missed")
        store.add(missed)
        session.begin(with: [missed], mode: .flashcard)
        XCTAssertEqual(session.total, 1)

        session.record(.again, for: missed, in: store)

        XCTAssertEqual(session.total, 2, "a forgotten word comes round again this session")
    }

    func testASuccessDoesNotRequeue() async throws {
        let store = makeStore()
        let session = makeSession()
        let known = word("known")
        store.add(known)
        session.begin(with: [known], mode: .flashcard)

        session.record(.good, for: known, in: store)

        XCTAssertEqual(session.total, 1)
    }

    /// Cram is the promise that practice won't disturb the schedule.
    func testCramLeavesTheScheduleUntouched() async throws {
        let store = makeStore()
        let session = makeSession()
        session.cram = true
        let word = word("orbit")
        store.add(word)
        let scheduledBefore = store.words.first?.nextReviewAt
        let reviewsBefore = store.words.first?.reviewCount

        session.begin(with: [word], mode: .flashcard)
        session.record(.good, for: word, in: store)

        XCTAssertEqual(store.words.first?.nextReviewAt, scheduledBefore)
        XCTAssertEqual(store.words.first?.reviewCount, reviewsBefore)
        XCTAssertEqual(session.goodCount, 1, "the session still counts it")
    }

    func testNonCramSchedulesThroughTheStore() async throws {
        let store = makeStore()
        let session = makeSession()
        let word = word("orbit")
        store.add(word)
        session.begin(with: [word], mode: .flashcard)

        session.record(.good, for: word, in: store)

        XCTAssertEqual(store.words.first?.reviewCount, 1)
        XCTAssertNotNil(store.words.first?.nextReviewAt)
    }

    func testCramStillRequeuesALapse() async throws {
        let store = makeStore()
        let session = makeSession()
        session.cram = true
        let missed = word("missed")
        store.add(missed)
        session.begin(with: [missed], mode: .flashcard)

        session.record(.again, for: missed, in: store)

        XCTAssertEqual(session.total, 2)
        XCTAssertEqual(store.words.first?.reviewCount, 0, "still no scheduling")
    }

    // MARK: - Objective accuracy

    func testAccuracyIsNilUntilSomethingIsGraded() async throws {
        let session = makeSession()
        session.begin(with: [word("one")], mode: .flashcard)
        XCTAssertNil(session.accuracy, "flashcards have no objective answer to score")
    }

    func testAccuracyTracksGradedAnswers() async throws {
        let session = makeSession()
        session.begin(with: [word("one")], mode: .typed)

        session.recordObjectiveAnswer(correct: true)
        session.recordObjectiveAnswer(correct: false)
        session.recordObjectiveAnswer(correct: true)
        session.recordObjectiveAnswer(correct: true)

        XCTAssertEqual(session.accuracy ?? 0, 0.75, accuracy: 0.0001)
    }

    // MARK: - Round-based modes (matching)

    /// The game answers several words at once, so the run steps by a grid.
    func testAdvanceRoundStepsPastAWholeGrid() {
        let session = makeSession()
        session.begin(with: makeWords(12), mode: .matching)

        session.advanceRound(of: 5, mode: .matching)

        XCTAssertEqual(session.position, 6)
        XCTAssertFalse(session.isFinished)
    }

    func testAdvanceRoundFinishesWhenTheQueueRunsOut() {
        let session = makeSession()
        session.begin(with: makeWords(4), mode: .matching)

        session.advanceRound(of: 5, mode: .matching)

        XCTAssertTrue(session.isFinished)
    }

    func testUpcomingReturnsOneGridsWorth() {
        let session = makeSession()
        session.begin(with: makeWords(12), mode: .matching)

        XCTAssertEqual(session.upcoming(5).count, 5)
        session.advanceRound(of: 5, mode: .matching)
        XCTAssertEqual(session.upcoming(5).count, 5)
        session.advanceRound(of: 5, mode: .matching)
        // Last grid is short rather than padded.
        XCTAssertEqual(session.upcoming(5).count, 2)
    }

    func testRoundCountersDescribeTheRunInGrids() {
        let session = makeSession()
        session.begin(with: makeWords(12), mode: .matching)

        XCTAssertEqual(session.roundPosition(of: 5), 1)
        session.advanceRound(of: 5, mode: .matching)
        XCTAssertEqual(session.roundPosition(of: 5), 2)
    }

    /// 12 words is two full grids and a leftover of two — too small to play,
    /// so it isn't counted or shown.
    func testPlayableRoundsIgnoreALeftoverTooSmallToPlay() {
        let session = makeSession()
        session.begin(with: makeWords(12), mode: .matching)
        XCTAssertEqual(session.playableRounds(of: 5, minimum: 4), 2)

        session.begin(with: makeWords(14), mode: .matching)
        XCTAssertEqual(session.playableRounds(of: 5, minimum: 4), 3)
    }

    /// The bug this guards: a run whose leftover slice can't fill a grid used
    /// to leave a dead round on screen with no way forward.
    func testRunEndsWhenTooFewWordsRemainForAnotherGrid() {
        let session = makeSession()
        session.begin(with: makeWords(7), mode: .matching)

        session.advanceRound(of: 5, minimumRemaining: 4, mode: .matching)

        XCTAssertTrue(session.isFinished, "two leftover words can't fill a grid")
    }

    func testRunContinuesWhenTheLeftoverIsStillPlayable() {
        let session = makeSession()
        session.begin(with: makeWords(9), mode: .matching)

        session.advanceRound(of: 5, minimumRemaining: 4, mode: .matching)

        XCTAssertFalse(session.isFinished)
        XCTAssertEqual(session.upcoming(5).count, 4)
    }

    /// The decision that defines this mode: a game never reaches the store.
    func testMatchingModeDoesNotAffectTheSchedule() {
        XCTAssertFalse(QuizMode.matching.affectsSchedule)
        XCTAssertTrue(QuizMode.matching.isRoundBased)
        for mode in QuizMode.allCases where mode != .matching {
            XCTAssertTrue(mode.affectsSchedule, "\(mode) should still schedule")
            XCTAssertFalse(mode.isRoundBased, "\(mode) asks one card at a time")
        }
    }

    // MARK: - Helpers

    private func word(_ term: String) -> SavedWord {
        SavedWord(term: term)
    }

    private func makeWords(_ count: Int) -> [SavedWord] {
        (0..<count).map { word("term\($0)") }
    }

    private func makeStore() -> SavedWordsStore {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let store = SavedWordsStore(fileURL: fileURL)
        Self.retainedStores.append(store)
        addTeardownBlock { try? FileManager.default.removeItem(at: fileURL) }
        return store
    }
}
