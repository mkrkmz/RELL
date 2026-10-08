//
//  StudyRoomTests.swift
//  Reader for Language LearnerTests
//
//  v15 Sprint 2 — the study room: what a session is made of, taking back a
//  grade and skipping a card, the rating buttons' "comes back in", the
//  summary, and the room's screens fitting its smallest window.
//

import SwiftUI
import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class StudyRoomTests: XCTestCase {

    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    // MARK: Queue

    func testReviewsComeOldestDueFirstWithNewWordsSpreadAmongThem() async {
        var words = (1...6).map { review("r\($0)", dueDaysAgo: Double(7 - $0)) }   // r1 most overdue
        words += (1...3).map { fresh("n\($0)", savedDaysAgo: Double(10 - $0)) }      // n1 saved first
        let queue = StudyPlan(size: 20, source: .all, newLimit: 2).queue(from: words, at: now).map(\.term)

        XCTAssertEqual(queue, ["r1", "r2", "n1", "r3", "r4", "n2", "r5", "r6"],
                       "two new words land after the 2nd and the 4th review")
    }

    func testTheSizeCapsReviewsAndLeavesRoomForNewWords() async {
        let words = (1...30).map { review("r\($0)", dueDaysAgo: 1) } + (1...8).map { fresh("n\($0)") }
        let queue = StudyPlan(size: 20, source: .all, newLimit: 5).queue(from: words, at: now)
        XCTAssertEqual(queue.count, 20)
        XCTAssertEqual(queue.count { !$0.hasBeenReviewed }, 5)

        let all = StudyPlan(size: 0, source: .all, newLimit: 0).queue(from: words, at: now)
        XCTAssertEqual(all.count, 30, "all waiting, no new words")
    }

    func testWordsNotDueStayOutAndPracticeTakesThem() async {
        let words = [review("due", dueDaysAgo: 1), review("later", dueDaysAgo: -3)]
        let plan = StudyPlan(size: 20, source: .all, newLimit: 0)
        XCTAssertEqual(plan.queue(from: words, at: now).map(\.term), ["due"])
        XCTAssertEqual(plan.practiceQueue(from: words, at: now).map(\.term), ["later"])
    }

    func testSourcesNarrowThePool() async {
        var book = review("book", dueDaysAgo: 1); book.pdfFilename = "Crime and Punishment"
        var deck = review("deck", dueDaysAgo: 1); deck.tags = ["Okul"]
        var hard = review("hard", dueDaysAgo: -5); hard.incorrectCount = 3
        var hardest = review("hardest", dueDaysAgo: -9); hardest.incorrectCount = 5
        let words = [book, deck, hard, hardest, review("other", dueDaysAgo: 1)]
        func terms(_ source: StudySource) -> [String] {
            StudyPlan(size: 20, source: source, newLimit: 5).queue(from: words, at: now).map(\.term)
        }
        XCTAssertEqual(terms(.book("Crime and Punishment")), ["book"])
        XCTAssertEqual(terms(.deck("okul")), ["deck"], "decks match case-insensitively")
        XCTAssertEqual(terms(.struggling), ["hardest", "hard"], "due or not, most-forgotten first")
    }

    // MARK: Take back and skip

    func testTakingBackAGradeRestoresTheScheduleAndTheCard() async throws {
        let store = makeStore()
        let words = ["one", "two", "three"].map { SavedWord(term: $0) }
        words.forEach(store.add)
        let session = QuizSession()
        session.begin(with: words, mode: .flashcard, shuffle: false)

        session.record(.again, for: words[0], in: store)
        session.advance(mode: .flashcard)
        XCTAssertEqual(session.queue.count, 4, "Again puts the word back")
        XCTAssertEqual(store.word(withID: words[0].id)?.reviewCount, 1)

        XCTAssertTrue(session.undoLast(in: store, mode: .flashcard))
        XCTAssertEqual(session.queue.map(\.term), ["one", "two", "three"])
        XCTAssertEqual(session.currentWord?.term, "one")
        XCTAssertEqual(session.againCount, 0)
        XCTAssertTrue(session.answers.isEmpty)
        let restored = try XCTUnwrap(store.word(withID: words[0].id))
        XCTAssertEqual(restored.reviewCount, 0)
        XCTAssertNil(restored.nextReviewAt)
        XCTAssertFalse(session.undoLast(in: store, mode: .flashcard), "nothing left to take back")
    }

    func testTakingBackAfterASkipRemovesTheRightCard() async {
        let store = makeStore()
        let words = ["a", "b", "c"].map { SavedWord(term: $0) }
        words.forEach(store.add)
        let session = QuizSession()
        session.begin(with: words, mode: .flashcard, shuffle: false)

        session.record(.again, for: words[0], in: store)   // queue: a b c a
        session.advance(mode: .flashcard)
        session.skipCurrent(mode: .flashcard)              // queue: a c a b
        XCTAssertEqual(session.queue.map(\.term), ["a", "c", "a", "b"])

        session.undoLast(in: store, mode: .flashcard)
        XCTAssertEqual(session.queue.map(\.term), ["a", "c", "b"], "the Again copy goes, the skipped card stays")
        XCTAssertEqual(session.currentWord?.term, "a")
    }

    func testSkipPutsTheCardLastButNotTheLastCard() async {
        let session = QuizSession()
        session.begin(with: ["a", "b"].map { SavedWord(term: $0) }, mode: .flashcard, shuffle: false)
        session.skipCurrent(mode: .flashcard)
        XCTAssertEqual(session.queue.map(\.term), ["b", "a"])
        session.advance(mode: .flashcard)
        session.skipCurrent(mode: .flashcard)
        XCTAssertEqual(session.queue.map(\.term), ["b", "a"], "nothing to skip to")
    }

    // MARK: Comes back in

    func testThePreviewIsWhatTheGradeDoes() async throws {
        let store = makeStore()
        var word = SavedWord(term: "manure")
        word.reviewCount = 2
        word.lastReviewedAt = now.addingTimeInterval(-4 * 86_400)
        word.stability = 4; word.difficulty = 5
        word.nextReviewAt = now
        store.add(word)
        for rating in ReviewRating.allCases {
            let preview = store.nextReviewDate(for: word, after: rating, at: now)
            let real = SavedWordsStore.reviewed(try XCTUnwrap(store.word(withID: word.id)), rating: rating, at: now).nextReviewAt
            XCTAssertEqual(preview, real, "\(rating)")
        }
        XCTAssertEqual(store.word(withID: word.id)?.reviewCount, 2, "a preview writes nothing")
    }

    func testIntervalLabels() async {
        XCTAssertTrue(StudyPlan.intervalLabel(from: now, to: now.addingTimeInterval(600)).contains("10"))
        XCTAssertTrue(StudyPlan.intervalLabel(from: now, to: now.addingTimeInterval(3 * 86_400 + 20 * 3_600)).contains("4"),
                      "whole days")
    }

    // MARK: Summary

    func testSummarySplitsRememberedStruggledAndSettled() async {
        let a = UUID(), b = UUID(), c = UUID()
        let answers: [QuizSession.Answer] = [
            .init(wordID: a, term: "a", rating: .good, nextReviewAt: now.addingTimeInterval(9 * 86_400)),
            .init(wordID: b, term: "b", rating: .again, nextReviewAt: now.addingTimeInterval(600)),
            .init(wordID: c, term: "c", rating: .hard, nextReviewAt: now.addingTimeInterval(86_400)),
            .init(wordID: b, term: "b", rating: .good, nextReviewAt: now.addingTimeInterval(86_400)),
        ]
        let summary = StudySummary(answers: answers, startedAt: now.addingTimeInterval(-300), now: now)
        XCTAssertEqual(summary.remembered, 2)
        XCTAssertEqual(summary.struggled.map(\.term), ["b"])
        XCTAssertEqual(summary.settled.map(\.term), ["a"])
        XCTAssertEqual(summary.duration, 300)
    }

    // MARK: Layout

    /// The room's smallest window is 720×560: setup and summary stay inside it.
    func testSetupAndSummaryFitTheSmallestWindow() async throws {
        let store = makeStore()
        for index in 0..<40 { store.add(SavedWord(term: "word\(index)", pdfFilename: "Harry Potter and the Chamber of Secrets", tags: ["Okul"])) }
        let setup = StudySetupView(
            store: store,
            lastDocument: RecentDocument(path: "/Books/Harry Potter and the Chamber of Secrets.epub",
                                         filename: "Harry Potter and the Chamber of Secrets"),
            availableModes: QuizMode.allCases, quizMode: .constant(.flashcard),
            typedAutoGrade: .constant(true), onStart: { _, _ in }
        )
        let setupHeight = try await LayoutGuard.settledHeight(of: setup, width: 720, height: 560)
        XCTAssertLessThanOrEqual(setupHeight, 560 + 1, "setup forced the window to \(setupHeight) pt")

        let session = QuizSession()
        let words = store.words
        session.begin(with: words, mode: .flashcard, shuffle: false)
        for word in words { session.record(.again, for: word, in: store) }
        session.finish()
        let summary = StudySummaryView(session: session, store: store, mode: .flashcard,
                                       onStudyAgain: { _ in }, onMore: {}, onClose: {})
        let summaryHeight = try await LayoutGuard.settledHeight(of: summary, width: 720, height: 560)
        XCTAssertLessThanOrEqual(summaryHeight, 560 + 1, "summary forced the window to \(summaryHeight) pt")
    }

    // MARK: Helpers

    private func review(_ term: String, dueDaysAgo: Double) -> SavedWord {
        var word = SavedWord(term: term)
        word.reviewCount = 1
        word.lastReviewedAt = now.addingTimeInterval(-(dueDaysAgo + 3) * 86_400)
        word.nextReviewAt = now.addingTimeInterval(-dueDaysAgo * 86_400)
        return word
    }

    private func fresh(_ term: String, savedDaysAgo: Double = 1) -> SavedWord {
        SavedWord(term: term, savedAt: now.addingTimeInterval(-savedDaysAgo * 86_400))
    }

    private func makeStore() -> SavedWordsStore {
        SavedWordsStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("w.json"))
    }
}
