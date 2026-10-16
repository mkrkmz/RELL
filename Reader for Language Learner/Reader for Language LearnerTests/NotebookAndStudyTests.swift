//
//  NotebookAndStudyTests.swift
//  Reader for Language LearnerTests
//
//  v18 Sprint 5 — the word notebook and the study room: one status language
//  (a mark and a word for every state, "you keep forgetting" ahead of the
//  rest), memory in words, the session's trail and streak of remembered
//  answers, the word page's history and its encounters grouped by book.
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class NotebookAndStudyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: Status

    func testEachStateHasItsOwnMarkAndWord() {
        let statuses: [WordStatus] = [.waiting, .new, .scheduled(now.addingTimeInterval(3 * 86_400)), .settled, .struggling]
        XCTAssertEqual(Set(statuses.map(\.symbol)).count, statuses.count, "a mark per state: it reads without colour")
        XCTAssertEqual(Set(statuses.map { $0.title(now: now) }).count, statuses.count)
        XCTAssertFalse(WordStatus.scheduled(now.addingTimeInterval(3 * 86_400)).title(now: now).isEmpty)
    }

    func testTheStatusOfAWord() {
        XCTAssertEqual(WordStatus.of(SavedWord(term: "new"), now: now), .new)
        // `reviewStatus` reads the clock, so these use today.
        let due = SavedWord(term: "due", reviewCount: 2, lastReviewedAt: Date().addingTimeInterval(-86_400),
                            nextReviewAt: Date().addingTimeInterval(-60))
        XCTAssertEqual(WordStatus.of(due), .waiting)
        let later = Date().addingTimeInterval(3 * 86_400)
        let scheduled = SavedWord(term: "later", reviewCount: 1, lastReviewedAt: Date(), nextReviewAt: later)
        XCTAssertEqual(WordStatus.of(scheduled), .scheduled(later))
        let settled = SavedWord(term: "settled", masteryLevel: .mastered, reviewCount: 6, lastReviewedAt: Date(),
                                nextReviewAt: Date().addingTimeInterval(30 * 86_400))
        XCTAssertEqual(WordStatus.of(settled), .settled)
    }

    func testForgettingAWordShowsAheadOfItsOtherState() {
        let word = SavedWord(term: "ricochet", reviewCount: 5, incorrectCount: StudyPlan.strugglingThreshold,
                             lastReviewedAt: now, nextReviewAt: now.addingTimeInterval(-60))
        XCTAssertEqual(WordStatus.of(word, now: now), .struggling, "due, but forgotten often: that comes first")
    }

    // MARK: Memory in words

    func testRecallStrengthThresholds() {
        XCTAssertEqual(RecallStrength(0.95), .strong)
        XCTAssertEqual(RecallStrength(0.8), .strong)
        XCTAssertEqual(RecallStrength(0.79), .fair)
        XCTAssertEqual(RecallStrength(0.5), .fair)
        XCTAssertEqual(RecallStrength(0.49), .weak)
        XCTAssertEqual(Set([RecallStrength.strong, .fair, .weak].map(\.title)).count, 3)
    }

    func testEachRatingLeavesItsOwnMark() {
        let marks = ReviewRating.allCases.map(\.mark)
        XCTAssertEqual(Set(marks).count, marks.count)
    }

    // MARK: The session's trail

    func testTheComboCountsRememberedAnswersFromTheLatestBack() {
        XCTAssertEqual(SessionTrail.combo([]), 0)
        XCTAssertEqual(SessionTrail.combo([.good, .easy, .hard]), 3)
        XCTAssertEqual(SessionTrail.combo([.good, .again, .good, .easy]), 2, "an Again breaks the run")
        XCTAssertEqual(SessionTrail.combo([.good, .good, .again]), 0)
    }

    func testTheTrailSaysItsCountsInWords() {
        let spoken = SessionTrail.spokenSummary([.good, .again, .easy], total: 20)
        XCTAssertTrue(spoken.contains("3"), spoken)
        XCTAssertTrue(spoken.contains("20"), spoken)
        XCTAssertTrue(spoken.contains("2"), "two remembered: \(spoken)")
        XCTAssertTrue(spoken.contains("1"), "one again: \(spoken)")
    }

    // MARK: Word page

    func testTheHistoryStripShowsTheLastAnswersOldestFirst() {
        let events = (0..<15).map { ReviewEvent(date: now.addingTimeInterval(Double(15 - $0) * 86_400), rating: $0 == 0 ? .easy : .good) }
        let word = SavedWord(term: "quay", reviewEvents: events)
        let recent = WordPageModel.recentAnswers(word)
        XCTAssertEqual(recent.count, 12)
        XCTAssertEqual(recent.map(\.date), recent.map(\.date).sorted(), "oldest first, whatever the stored order")
        XCTAssertEqual(recent.last?.rating, .easy, "the latest answer is last")
    }

    func testEncountersAreGroupedByBookInTheOrderTheyCame() {
        let id = UUID()
        func met(_ title: String, _ times: Int) -> WordEncounter {
            WordEncounter(wordID: id, documentPath: "/\(title)", documentTitle: title, location: 1, isEPUB: true,
                          sentence: "…", occurrences: times, date: now)
        }
        let all = [met("Harbour Lights", 2), met("The Long Shore", 1), met("Harbour Lights", 1), met("Harbour Lights", 0)]
        let groups = WordPageModel.groupedByBook(Array(all.prefix(3)), all: all)
        XCTAssertEqual(groups.map(\.title), ["Harbour Lights", "The Long Shore"])
        XCTAssertEqual(groups.first?.encounters.count, 2, "only the shown ones are listed")
        XCTAssertEqual(groups.first?.times, 4, "every time it turned up counts, a page with no count as once")
        XCTAssertEqual(groups.last?.times, 1)
    }

    // MARK: Reading screen

    func testPassageDifficultyHasAWordForEachColour() {
        let titles = [LexicalProfile.Difficulty.comfortable, .challenging, .demanding].map(\.localizedTitle)
        XCTAssertEqual(Set(titles).count, 3)
    }
}
