//
//  ReviewStreakTests.swift
//  Reader for Language LearnerTests
//
//  `ReviewStreakCalculator` is a pure function over (review days, today) — no
//  stores, no persistence — so these tests just feed day offsets and assert
//  the streak/freeze outcome. No CI static-retain convention needed.
//

import XCTest
@testable import Reader_for_Language_Learner

final class ReviewStreakTests: XCTestCase {

    private let calendar = Calendar.current
    private lazy var today = calendar.startOfDay(for: Date())

    /// A review date `daysAgo` before today.
    private func day(_ daysAgo: Int) -> Date {
        calendar.date(byAdding: .day, value: -daysAgo, to: today)!
    }

    private func streak(_ agos: [Int]) -> ReviewStreak {
        ReviewStreakCalculator.compute(reviewDays: agos.map(day), today: today, calendar: calendar)
    }

    // MARK: - Basics

    func testNoReviewsIsEmpty() {
        XCTAssertEqual(streak([]), .empty)
    }

    func testReviewedTodayOnly() {
        let s = streak([0])
        XCTAssertEqual(s.current, 1)
        XCTAssertEqual(s.longest, 1)
        XCTAssertFalse(s.isAtRiskToday)
    }

    func testConsecutiveDaysThroughToday() {
        let s = streak([0, 1, 2, 3])
        XCTAssertEqual(s.current, 4)
        XCTAssertEqual(s.longest, 4)
        XCTAssertFalse(s.isAtRiskToday)
    }

    func testDuplicateSameDayCountsOnce() {
        // Two review events on the same calendar day must not double-count.
        let morning = calendar.date(byAdding: .hour, value: 3, to: today)!   // today 03:00
        let evening = calendar.date(byAdding: .hour, value: 20, to: today)!  // today 20:00
        let s = ReviewStreakCalculator.compute(reviewDays: [morning, evening], today: today, calendar: calendar)
        XCTAssertEqual(s.current, 1)
    }

    // MARK: - Grace for "today not reviewed yet"

    func testReviewedThroughYesterdayIsAtRisk() {
        let s = streak([1, 2, 3])
        XCTAssertEqual(s.current, 3, "Missing today alone must not break the streak")
        XCTAssertTrue(s.isAtRiskToday)
    }

    // MARK: - Breaking

    func testGapBreaksStreakWithoutFreeze() {
        // 5 consecutive days ending 3 days ago; a 2-day gap and no earned freeze.
        let s = streak([3, 4, 5, 6, 7])
        XCTAssertEqual(s.current, 0)
        XCTAssertEqual(s.longest, 5, "Longest still records the broken run")
    }

    // MARK: - Earning freezes

    func testEarnsOneFreezeAtSevenDays() {
        let s = streak(Array(0...6))   // 7 consecutive days
        XCTAssertEqual(s.current, 7)
        XCTAssertEqual(s.freezesRemaining, 1)
    }

    func testFreezesCapAtTwo() {
        let s = streak(Array(0...20))  // 21 consecutive days → 3 milestones, capped at 2
        XCTAssertEqual(s.current, 21)
        XCTAssertEqual(s.freezesRemaining, ReviewStreakCalculator.maxFreezes)
    }

    // MARK: - Auto-freeze bridging

    func testEarnedFreezeBridgesASingleMissedDay() {
        // 8 consecutive days ending 2 days ago (earns 1 freeze at day 7), then
        // one missed day at "yesterday", today not yet reviewed.
        let s = streak([2, 3, 4, 5, 6, 7, 8, 9])
        XCTAssertEqual(s.current, 8, "The freeze should bridge the single missed day")
        XCTAssertEqual(s.freezesRemaining, 0, "Bridging consumes the earned freeze")
        XCTAssertTrue(s.isAtRiskToday)
    }

    func testGapLargerThanFreezesBreaks() {
        // 7 consecutive days (1 freeze) ending 4 days ago — a 3-day gap exceeds
        // the single freeze, so the streak lapses.
        let s = streak([4, 5, 6, 7, 8, 9, 10])
        XCTAssertEqual(s.current, 0)
    }

    func testFreezeBridgesGapMidHistoryThenContinues() {
        // A run, a single missed day bridged by an earned freeze, then more days
        // right up to today — the streak should span the whole span.
        // Days 0..6 earn a freeze; missed day at ago 7; days 8..14 before it.
        let recent = Array(0...6)          // 7 days ending today
        let older = Array(8...14)          // 7 days ending 8 days ago
        let s = streak(older + recent)     // gap at ago 7, bridged by the freeze earned in `older`
        XCTAssertEqual(s.current, 14, "Both runs join across the bridged day")
        XCTAssertFalse(s.isAtRiskToday, "Reviewed today")
    }
}
