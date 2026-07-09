//
//  SavedWordsStoreTests.swift
//  Reader for Language LearnerTests
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class SavedWordsStoreTests: XCTestCase {
    private static var retainedStores: [SavedWordsStore] = []

    func testPendingReviewCountsNewWords() {
        let store = makeStore()
        store.add(SavedWord(term: "orbit"))

        XCTAssertEqual(store.pendingReviewCount, 1)
        XCTAssertEqual(store.newCount, 1)
    }

    func testApplyGoodPromotesNewWordToLearning() {
        let store = makeStore()
        let word = SavedWord(term: "orbit")
        store.add(word)

        let updated = store.applyReview(.good, to: word)

        XCTAssertEqual(updated?.masteryLevel, .learning)
        XCTAssertEqual(updated?.reviewCount, 1)
        XCTAssertNotNil(updated?.lastReviewedAt)
        XCTAssertEqual(updated?.reviewHistory.count, 1)
        XCTAssertNotNil(updated?.nextReviewAt)
    }

    func testApplyAgainKeepsWordDueSoon() {
        let store = makeStore()
        let word = SavedWord(term: "orbit", masteryLevel: .learning, reviewCount: 1)
        store.add(word)

        let updated = store.applyReview(.again, to: word)

        XCTAssertEqual(updated?.incorrectCount, 1)
        XCTAssertEqual(updated?.masteryLevel, .learning)
        XCTAssertNotNil(updated?.nextReviewAt)
    }

    func testApplyAgainLowersEaseFactor() {
        let store = makeStore()
        let word = SavedWord(term: "orbit", masteryLevel: .learning, reviewCount: 1)
        store.add(word)

        let updated = store.applyReview(.again, to: word)

        XCTAssertEqual(updated?.easeFactor, 2.3)
    }

    func testApplyEasyRaisesEaseAndExtendsInterval() {
        let store = makeStore()
        let now = Date()
        let word = SavedWord(term: "orbit", masteryLevel: .mastered, reviewCount: 4)
        store.add(word)

        let updated = store.applyReview(.easy, to: word, reviewedAt: now)

        XCTAssertEqual(updated?.easeFactor, 2.65)
        // Base mastered interval is 14 days; ease 2.65/2.5 rounds the scaled
        // interval to 15 days.
        let expected = Calendar.current.date(byAdding: .day, value: 15, to: now)
        XCTAssertEqual(
            updated?.nextReviewAt.map { Calendar.current.startOfDay(for: $0) },
            expected.map { Calendar.current.startOfDay(for: $0) }
        )
    }

    func testDefaultEaseFactorPreservesFixedIntervals() {
        let store = makeStore()
        let now = Date()
        let word = SavedWord(term: "orbit", masteryLevel: .mastered, reviewCount: 4)
        store.add(word)

        let updated = store.applyReview(.good, to: word, reviewedAt: now)

        let expected = Calendar.current.date(byAdding: .day, value: 7, to: now)
        XCTAssertEqual(
            updated?.nextReviewAt.map { Calendar.current.startOfDay(for: $0) },
            expected.map { Calendar.current.startOfDay(for: $0) }
        )
    }

    func testSetCEFRLevelAssignsAndClears() {
        let store = makeStore()
        let word = SavedWord(term: "orbit")
        store.add(word)

        store.setCEFRLevel(.b2, for: word)
        XCTAssertEqual(store.words.first?.cefrLevel, "B2")

        store.setCEFRLevel(nil, for: word)
        XCTAssertNil(store.words.first?.cefrLevel)
    }

    func testReviewedTodayCountTracksReviewedWords() {
        let store = makeStore()
        let word = SavedWord(term: "orbit")
        store.add(word)
        _ = store.applyReview(.good, to: word, reviewedAt: Date())

        XCTAssertEqual(store.reviewedTodayCount, 1)
    }

    func testDocumentScopedCountsTrackSavedAndDueWords() {
        let store = makeStore()
        let now = Date()
        store.add(SavedWord(term: "orbit", pdfFilename: "astro", nextReviewAt: now.addingTimeInterval(-60)))
        store.add(SavedWord(term: "gravity", pdfFilename: "astro", masteryLevel: .mastered))
        store.add(SavedWord(term: "syntax", pdfFilename: "grammar", nextReviewAt: now.addingTimeInterval(-60)))

        XCTAssertEqual(store.savedCount(for: "astro"), 2)
        XCTAssertEqual(store.dueCount(for: "astro", at: now), 1)
        XCTAssertEqual(store.savedCount(for: "missing"), 0)
    }

    func testReviewQueuePrioritizesDueWords() {
        let store = makeStore()
        let now = Date()
        store.add(SavedWord(term: "due", nextReviewAt: now.addingTimeInterval(-60)))
        store.add(SavedWord(term: "future", nextReviewAt: now.addingTimeInterval(600)))
        store.add(SavedWord(term: "mastered", masteryLevel: .mastered, nextReviewAt: now.addingTimeInterval(600)))

        let queue = store.reviewQueue(includeAll: false, at: now)

        XCTAssertEqual(queue.map(\.term), ["due"])
    }

    func testReviewQueueFallsBackToNonMasteredWordsWhenNothingIsDue() {
        let store = makeStore()
        let now = Date()
        store.add(SavedWord(term: "learning", masteryLevel: .learning, nextReviewAt: now.addingTimeInterval(600)))
        store.add(SavedWord(term: "new", nextReviewAt: now.addingTimeInterval(600)))
        store.add(SavedWord(term: "mastered", masteryLevel: .mastered, nextReviewAt: now.addingTimeInterval(600)))

        let queue = store.reviewQueue(includeAll: false, at: now)

        XCTAssertEqual(Set(queue.map(\.term)), Set(["learning", "new"]))
    }

    func testReviewQueueIncludeAllReturnsAllSavedWords() {
        let store = makeStore()
        let now = Date()
        store.add(SavedWord(term: "due", nextReviewAt: now.addingTimeInterval(-60)))
        store.add(SavedWord(term: "mastered", masteryLevel: .mastered, nextReviewAt: now.addingTimeInterval(600)))

        let queue = store.reviewQueue(includeAll: true, at: now)

        XCTAssertEqual(Set(queue.map(\.term)), Set(["due", "mastered"]))
    }

    func testReviewActivityCountsReviewedWordsByDay() {
        let store = makeStore()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        store.add(SavedWord(term: "today-one", reviewHistory: [today.addingTimeInterval(60)]))
        store.add(SavedWord(term: "today-two", reviewHistory: [today.addingTimeInterval(120)]))
        store.add(SavedWord(term: "yesterday", reviewHistory: [yesterday.addingTimeInterval(60)]))
        store.add(SavedWord(term: "unreviewed"))

        let activity = store.reviewActivity(days: 2, endingAt: today)

        XCTAssertEqual(activity.map(\.count), [1, 2])
    }

    func testReviewActivityCountsMultipleReviewsForSameWord() {
        let store = makeStore()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let word = SavedWord(term: "orbit")
        store.add(word)

        _ = store.applyReview(.good, to: word, reviewedAt: yesterday.addingTimeInterval(60))
        guard let reviewedYesterday = store.words.first else {
            XCTFail("Expected reviewed word")
            return
        }
        _ = store.applyReview(.good, to: reviewedYesterday, reviewedAt: today.addingTimeInterval(60))

        let activity = store.reviewActivity(days: 2, endingAt: today)

        XCTAssertEqual(activity.map(\.count), [1, 1])
        XCTAssertEqual(store.words.first?.reviewHistory.count, 2)
    }

    func testReviewActivityFallsBackToLegacyLastReviewedAt() {
        let store = makeStore()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        store.add(SavedWord(term: "legacy", lastReviewedAt: today.addingTimeInterval(60)))

        let activity = store.reviewActivity(days: 1, endingAt: today)

        XCTAssertEqual(activity.first?.count, 1)
    }

    private func makeStore() -> SavedWordsStore {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let store = SavedWordsStore(fileURL: fileURL)
        Self.retainedStores.append(store)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: fileURL)
        }
        return store
    }
}
