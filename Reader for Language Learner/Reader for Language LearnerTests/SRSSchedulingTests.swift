//
//  SRSSchedulingTests.swift
//  Reader for Language LearnerTests
//
//  Scheduling behaviour of `SavedWordsStore.applyReview`.
//
//  Originally (v1.29) this pinned the hand-rolled SM-2-lite intervals as a
//  regression net for the FSRS migration. FSRS landed in v1.31, so the exact
//  interval expectations were *intentionally* rewritten here; the bookkeeping
//  and mastery invariants that must survive any scheduler are unchanged, and
//  the pure model itself is covered by `FSRSSchedulerTests`.
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class SRSSchedulingTests: XCTestCase {
    private static var retainedStores: [SavedWordsStore] = []

    // MARK: - FSRS-driven intervals

    /// A first "good" schedules the initial good stability (~3.7 days).
    func testGoodOnNewWordSchedulesInitialGoodStability() {
        let store = makeStore()
        let now = Date()
        let word = SavedWord(term: "orbit")
        store.add(word)

        let updated = store.applyReview(.good, to: word, reviewedAt: now)

        assertDayInterval(updated?.nextReviewAt, days: 4, from: now)
        XCTAssertEqual(updated?.stability ?? 0, FSRSScheduler.defaultWeights[2], accuracy: 0.0001)
    }

    func testEasyOnNewWordSchedulesMuchFurtherOut() {
        let store = makeStore()
        let now = Date()
        let word = SavedWord(term: "orbit")
        store.add(word)

        let updated = store.applyReview(.easy, to: word, reviewedAt: now)

        assertDayInterval(updated?.nextReviewAt, days: 14, from: now)
    }

    func testHardOnNewWordSchedulesSoonest() {
        let store = makeStore()
        let now = Date()
        let word = SavedWord(term: "orbit")
        store.add(word)

        let updated = store.applyReview(.hard, to: word, reviewedAt: now)

        assertDayInterval(updated?.nextReviewAt, days: 1, from: now)
    }

    /// A lapse still returns the word within the session rather than waiting
    /// out the sub-day interval a collapsed stability would imply.
    func testAgainReschedulesTenMinutesOut() {
        let store = makeStore()
        let now = Date()
        let word = SavedWord(term: "orbit")
        store.add(word)

        let updated = store.applyReview(.again, to: word, reviewedAt: now)

        let expected = Calendar.current.date(byAdding: .minute, value: 10, to: now)
        XCTAssertEqual(updated?.nextReviewAt, expected)
        XCTAssertEqual(updated?.incorrectCount, 1)
    }

    func testGradesOrderTheNextIntervals() {
        let now = Date()
        func interval(for rating: ReviewRating) -> TimeInterval {
            let store = makeStore()
            let word = SavedWord(term: "orbit")
            store.add(word)
            let updated = store.applyReview(rating, to: word, reviewedAt: now)
            return updated?.nextReviewAt?.timeIntervalSince(now) ?? 0
        }
        XCTAssertLessThan(interval(for: .again), interval(for: .hard))
        XCTAssertLessThan(interval(for: .hard), interval(for: .good))
        XCTAssertLessThan(interval(for: .good), interval(for: .easy))
    }

    func testRepeatedSuccessfulReviewsLengthenTheInterval() {
        let store = makeStore()
        let start = Date()
        let word = SavedWord(term: "orbit")
        store.add(word)

        var reviewedAt = start
        var previousGap: TimeInterval = 0
        for step in 0..<4 {
            guard let current = store.words.first else { return XCTFail("word missing") }
            guard let updated = store.applyReview(.good, to: current, reviewedAt: reviewedAt),
                  let next = updated.nextReviewAt
            else { return XCTFail("expected a scheduled date") }
            let gap = next.timeIntervalSince(reviewedAt)
            if step > 0 {
                XCTAssertGreaterThan(gap, previousGap, "each successful review should space it out further")
            }
            previousGap = gap
            reviewedAt = next   // review exactly when due
        }
    }

    // MARK: - Mastery is a read-out of memory strength

    func testMasteryBecomesLearningOnFirstReview() {
        let store = makeStore()
        let word = SavedWord(term: "orbit")
        store.add(word)

        let updated = store.applyReview(.good, to: word)

        XCTAssertEqual(updated?.masteryLevel, .learning)
    }

    func testDurableStabilityEarnsMastered() {
        let store = makeStore()
        let now = Date()
        // A word already remembered for ~25 days: another success keeps it
        // above the mastery threshold.
        let word = SavedWord(
            term: "orbit",
            masteryLevel: .learning,
            reviewCount: 5,
            lastReviewedAt: now.addingTimeInterval(-25 * 86_400),
            stability: 25,
            difficulty: 5
        )
        store.add(word)

        let updated = store.applyReview(.good, to: word, reviewedAt: now)

        XCTAssertEqual(updated?.masteryLevel, .mastered)
        XCTAssertGreaterThanOrEqual(updated?.stability ?? 0, FSRSScheduler.masteredStabilityThreshold)
    }

    func testLapseDemotesMasteredWordToLearning() {
        let store = makeStore()
        let now = Date()
        let word = SavedWord(
            term: "orbit",
            masteryLevel: .mastered,
            reviewCount: 6,
            lastReviewedAt: now.addingTimeInterval(-30 * 86_400),
            stability: 40,
            difficulty: 5
        )
        store.add(word)

        let updated = store.applyReview(.again, to: word, reviewedAt: now)

        XCTAssertEqual(updated?.masteryLevel, .learning)
        XCTAssertLessThanOrEqual(updated?.stability ?? .infinity, 40, "a lapse must not extend stability")
    }

    // MARK: - Migration from the legacy SM-2 fields

    /// A pre-FSRS word carries its old schedule into a seeded memory state
    /// instead of restarting as if it were new.
    func testLegacyWordSeedsStabilityFromItsOldInterval() {
        let store = makeStore()
        let now = Date()
        let word = SavedWord(
            term: "orbit",
            masteryLevel: .mastered,
            reviewCount: 4,
            lastReviewedAt: now.addingTimeInterval(-14 * 86_400),
            nextReviewAt: now,           // a 14-day interval had been set
            easeFactor: 2.5
        )
        store.add(word)
        XCTAssertNil(store.words.first?.stability, "precondition: not yet migrated")

        let updated = store.applyReview(.good, to: word, reviewedAt: now)

        XCTAssertNotNil(updated?.stability)
        XCTAssertNotNil(updated?.difficulty)
        // Seeded at the old 14-day interval, then grown by a successful review.
        XCTAssertGreaterThan(updated?.stability ?? 0, 14)
    }

    func testLegacyEaseMapsOntoDifficultyOnMigration() {
        let store = makeStore()
        let now = Date()
        let easyWord = SavedWord(term: "easy", reviewCount: 3,
                                 lastReviewedAt: now.addingTimeInterval(-86_400), easeFactor: 3.2)
        let hardWord = SavedWord(term: "hard", reviewCount: 3,
                                 lastReviewedAt: now.addingTimeInterval(-86_400), easeFactor: 1.5)
        store.add(easyWord)
        store.add(hardWord)

        let easyUpdated = store.applyReview(.good, to: easyWord, reviewedAt: now)
        let hardUpdated = store.applyReview(.good, to: hardWord, reviewedAt: now)

        XCTAssertLessThan(
            easyUpdated?.difficulty ?? 10,
            hardUpdated?.difficulty ?? 0,
            "the word the old engine found easy should migrate to a lower difficulty"
        )
    }

    // MARK: - Bookkeeping invariants (scheduler-independent)

    func testApplyReviewReturnsNilForWordNotInStore() {
        let store = makeStore()
        XCTAssertNil(store.applyReview(.good, to: SavedWord(term: "never-added")))
    }

    func testApplyReviewAlwaysIncrementsReviewCountAndWritesBothHistories() {
        let store = makeStore()
        let now = Date()
        let word = SavedWord(term: "orbit")
        store.add(word)

        let updated = store.applyReview(.again, to: word, reviewedAt: now)

        XCTAssertEqual(updated?.reviewCount, 1)
        XCTAssertEqual(updated?.reviewHistory, [now])
        XCTAssertEqual(updated?.reviewEvents.count, 1)
        XCTAssertEqual(updated?.reviewEvents.first?.rating, .again)
        XCTAssertEqual(updated?.lastReviewedAt, now)
    }

    func testApplyReviewFoldsLegacyLastReviewedIntoHistory() {
        let store = makeStore()
        let earlier = Date().addingTimeInterval(-3600)
        let now = Date()
        let word = SavedWord(term: "orbit", masteryLevel: .learning, reviewCount: 1, lastReviewedAt: earlier)
        store.add(word)

        let updated = store.applyReview(.good, to: word, reviewedAt: now)

        XCTAssertEqual(updated?.reviewHistory, [earlier, now])
    }

    /// Ease is no longer the scheduler, but it keeps being maintained so an
    /// older build can still read the file and the FSRS seed stays meaningful.
    func testLegacyEaseFactorIsStillMaintained() {
        let store = makeStore()
        let word = SavedWord(term: "orbit", masteryLevel: .learning, reviewCount: 1)
        store.add(word)

        XCTAssertEqual(store.applyReview(.again, to: word)?.easeFactor ?? 0, 2.3, accuracy: 0.0001)

        guard let afterLapse = store.words.first else { return XCTFail("word missing") }
        XCTAssertEqual(store.applyReview(.easy, to: afterLapse)?.easeFactor ?? 0, 2.45, accuracy: 0.0001)
    }

    func testEaseFactorClampsAtBothEnds() {
        let store = makeStore()
        let floorWord = SavedWord(term: "floor", masteryLevel: .learning, reviewCount: 1, easeFactor: 1.4)
        let ceilWord  = SavedWord(term: "ceil",  masteryLevel: .learning, reviewCount: 1, easeFactor: 3.45)
        store.add(floorWord)
        store.add(ceilWord)

        XCTAssertEqual(store.applyReview(.again, to: floorWord)?.easeFactor ?? 0, 1.3, accuracy: 0.0001)
        XCTAssertEqual(store.applyReview(.easy, to: ceilWord)?.easeFactor ?? 0, 3.5, accuracy: 0.0001)
    }

    // MARK: - Helpers

    private func assertDayInterval(
        _ date: Date?,
        days: Int,
        from reviewedAt: Date,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expected = Calendar.current.date(byAdding: .day, value: days, to: reviewedAt)
        XCTAssertEqual(
            date.map { Calendar.current.startOfDay(for: $0) },
            expected.map { Calendar.current.startOfDay(for: $0) },
            "expected +\(days)d",
            file: file,
            line: line
        )
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
