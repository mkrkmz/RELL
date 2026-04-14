//
//  SavedWordsStoreTests.swift
//  Reader for Language LearnerTests
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class SavedWordsStoreTests: XCTestCase {

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

    func testReviewedTodayCountTracksReviewedWords() {
        let store = makeStore()
        let word = SavedWord(term: "orbit")
        store.add(word)
        _ = store.applyReview(.good, to: word, reviewedAt: Date())

        XCTAssertEqual(store.reviewedTodayCount, 1)
    }

    private func makeStore() -> SavedWordsStore {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        return SavedWordsStore(fileURL: fileURL)
    }
}
