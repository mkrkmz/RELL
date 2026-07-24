//
//  SRSSchedulingTests.swift
//  Reader for Language LearnerTests
//
//  Full branch coverage of the SM-2-lite scheduler in
//  `SavedWordsStore.applyReview` — a deliberate regression net pinned BEFORE
//  the FSRS migration (Roadmap v9 Sprint 3) rewrites the scheduling math.
//  Every rating × mastery transition, both ease clamps, and the exact
//  short-interval durations are asserted here so any behavioural change in a
//  later refactor shows up as a failing test rather than a silent drift.
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class SRSSchedulingTests: XCTestCase {
    private static var retainedStores: [SavedWordsStore] = []

    // MARK: - Rating × mastery matrix

    func testGoodOnNewPromotesToLearningEightHoursOut() {
        let store = makeStore()
        let now = Date()
        let word = SavedWord(term: "orbit")   // .new, reviewCount 0
        store.add(word)

        let updated = store.applyReview(.good, to: word, reviewedAt: now)

        XCTAssertEqual(updated?.masteryLevel, .learning)
        let expected = Calendar.current.date(byAdding: .hour, value: 8, to: now)
        XCTAssertEqual(updated?.nextReviewAt, expected, "good/new schedules exactly +8h")
    }

    func testGoodOnLearningBelowThresholdStaysLearningOneDayOut() {
        let store = makeStore()
        let now = Date()
        // reviewCount 1 → increments to 2, still < 3, stays learning.
        let word = SavedWord(term: "orbit", masteryLevel: .learning, reviewCount: 1)
        store.add(word)

        let updated = store.applyReview(.good, to: word, reviewedAt: now)

        XCTAssertEqual(updated?.masteryLevel, .learning)
        XCTAssertEqual(updated?.reviewCount, 2)
        assertDayInterval(updated?.nextReviewAt, base: 1, from: now)
    }

    func testGoodOnLearningAtThresholdPromotesToMasteredThreeDaysOut() {
        let store = makeStore()
        let now = Date()
        // reviewCount 2 → increments to 3, hits the >= 3 promotion.
        let word = SavedWord(term: "orbit", masteryLevel: .learning, reviewCount: 2)
        store.add(word)

        let updated = store.applyReview(.good, to: word, reviewedAt: now)

        XCTAssertEqual(updated?.masteryLevel, .mastered)
        assertDayInterval(updated?.nextReviewAt, base: 3, from: now)
    }

    func testGoodOnMasteredSchedulesSevenDaysOut() {
        let store = makeStore()
        let now = Date()
        let word = SavedWord(term: "orbit", masteryLevel: .mastered, reviewCount: 4)
        store.add(word)

        let updated = store.applyReview(.good, to: word, reviewedAt: now)

        XCTAssertEqual(updated?.masteryLevel, .mastered)
        assertDayInterval(updated?.nextReviewAt, base: 7, from: now)
    }

    func testAgainOnNewStaysNewAndReschedulesTenMinutesOut() {
        let store = makeStore()
        let now = Date()
        let word = SavedWord(term: "orbit")   // .new
        store.add(word)

        let updated = store.applyReview(.again, to: word, reviewedAt: now)

        XCTAssertEqual(updated?.masteryLevel, .new, "again only demotes a mastered word")
        XCTAssertEqual(updated?.incorrectCount, 1)
        let expected = Calendar.current.date(byAdding: .minute, value: 10, to: now)
        XCTAssertEqual(updated?.nextReviewAt, expected, "again schedules exactly +10min")
    }

    func testAgainOnMasteredDemotesToLearning() {
        let store = makeStore()
        let word = SavedWord(term: "orbit", masteryLevel: .mastered, reviewCount: 5)
        store.add(word)

        let updated = store.applyReview(.again, to: word)

        XCTAssertEqual(updated?.masteryLevel, .learning, "a lapse on a mastered word demotes it")
        XCTAssertEqual(updated?.incorrectCount, 1)
    }

    func testEasyOnNewPromotesToLearningOneDayOut() {
        let store = makeStore()
        let now = Date()
        let word = SavedWord(term: "orbit")   // .new, ease 2.5
        store.add(word)

        let updated = store.applyReview(.easy, to: word, reviewedAt: now)

        XCTAssertEqual(updated?.masteryLevel, .learning)
        XCTAssertEqual(updated?.easeFactor ?? 0, 2.65, accuracy: 0.0001)
        // base 1 × (2.65/2.5) = 1.06 → rounds to 1 day.
        assertDayInterval(updated?.nextReviewAt, base: 1, from: now, easeScaled: 2.65)
    }

    func testEasyOnLearningPromotesToMasteredSevenDaysOut() {
        let store = makeStore()
        let now = Date()
        let word = SavedWord(term: "orbit", masteryLevel: .learning, reviewCount: 1)
        store.add(word)

        let updated = store.applyReview(.easy, to: word, reviewedAt: now)

        XCTAssertEqual(updated?.masteryLevel, .mastered)
        assertDayInterval(updated?.nextReviewAt, base: 7, from: now, easeScaled: 2.65)
    }

    func testEasyOnMasteredSchedulesFourteenDaysOut() {
        let store = makeStore()
        let now = Date()
        let word = SavedWord(term: "orbit", masteryLevel: .mastered, reviewCount: 6)
        store.add(word)

        let updated = store.applyReview(.easy, to: word, reviewedAt: now)

        XCTAssertEqual(updated?.masteryLevel, .mastered)
        assertDayInterval(updated?.nextReviewAt, base: 14, from: now, easeScaled: 2.65)
    }

    // MARK: - Ease-factor clamps

    func testEaseFactorFloorsAtOnePointThree() {
        let store = makeStore()
        // Ease already near the floor; another "again" must clamp, not undershoot.
        let word = SavedWord(term: "orbit", masteryLevel: .learning, reviewCount: 1, easeFactor: 1.4)
        store.add(word)

        let updated = store.applyReview(.again, to: word)

        XCTAssertEqual(updated?.easeFactor ?? 0, 1.3, accuracy: 0.0001, "1.4 - 0.2 clamps to the 1.3 floor")
    }

    func testEaseFactorCeilingsAtThreePointFive() {
        let store = makeStore()
        let word = SavedWord(term: "orbit", masteryLevel: .mastered, reviewCount: 4, easeFactor: 3.45)
        store.add(word)

        let updated = store.applyReview(.easy, to: word)

        XCTAssertEqual(updated?.easeFactor ?? 0, 3.5, accuracy: 0.0001, "3.45 + 0.15 clamps to the 3.5 ceiling")
    }

    func testGoodDoesNotChangeEaseFactor() {
        let store = makeStore()
        let word = SavedWord(term: "orbit", masteryLevel: .learning, reviewCount: 1, easeFactor: 2.5)
        store.add(word)

        let updated = store.applyReview(.good, to: word)

        XCTAssertEqual(updated?.easeFactor ?? 0, 2.5, accuracy: 0.0001, "good is ease-neutral")
    }

    // MARK: - Bookkeeping invariants

    func testApplyReviewReturnsNilForWordNotInStore() {
        let store = makeStore()
        let stray = SavedWord(term: "never-added")

        XCTAssertNil(store.applyReview(.good, to: stray))
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

    /// A word reviewed once through the legacy path (only `lastReviewedAt`,
    /// empty `reviewHistory`) must have that prior date folded into
    /// `reviewHistory` before the new date is appended, so its activity count
    /// doesn't silently lose the earlier review.
    func testApplyReviewFoldsLegacyLastReviewedIntoHistory() {
        let store = makeStore()
        let earlier = Date().addingTimeInterval(-3600)
        let now = Date()
        let word = SavedWord(term: "orbit", masteryLevel: .learning, reviewCount: 1, lastReviewedAt: earlier)
        store.add(word)

        let updated = store.applyReview(.good, to: word, reviewedAt: now)

        XCTAssertEqual(updated?.reviewHistory, [earlier, now])
    }

    // MARK: - Helpers

    /// Asserts `date` equals `reviewedAt + scheduledDate(base, ease)` where the
    /// scheduler scales the base-day interval by `easeScaled / 2.5` and rounds,
    /// with a floor of 1 day. Compared at day granularity to stay DST-robust.
    private func assertDayInterval(
        _ date: Date?,
        base: Int,
        from reviewedAt: Date,
        easeScaled: Double = 2.5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let scaledDays = max(1, Int((Double(base) * easeScaled / 2.5).rounded()))
        let expected = Calendar.current.date(byAdding: .day, value: scaledDays, to: reviewedAt)
        XCTAssertEqual(
            date.map { Calendar.current.startOfDay(for: $0) },
            expected.map { Calendar.current.startOfDay(for: $0) },
            "expected +\(scaledDays)d",
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
