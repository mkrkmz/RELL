//
//  ReadingProgressMathTests.swift
//  Reader for Language LearnerTests
//
//  Content-weighted book progress + time-remaining (Roadmap v9 Sprint 2, U3).
//

import XCTest
@testable import Reader_for_Language_Learner

final class ReadingProgressMathTests: XCTestCase {

    func testUniformWeightsMatchChapterFraction() {
        // Four equal chapters: halfway through chapter index 2 (the third) is
        // (2 + 0.5) / 4 = 0.625.
        let weights = [100, 100, 100, 100]
        let progress = ReadingProgressMath.bookProgress(weights: weights, chapterIndex: 2, scrollFraction: 0.5)
        XCTAssertEqual(progress, 0.625, accuracy: 0.0001)
    }

    func testWeightingReflectsChapterLengths() {
        // A huge first chapter dominates: finishing it (start of chapter 1)
        // should read near 0.9, not 0.25 that uniform weighting would give.
        let weights = [900, 40, 30, 30]
        let progress = ReadingProgressMath.bookProgress(weights: weights, chapterIndex: 1, scrollFraction: 0)
        XCTAssertEqual(progress, 0.9, accuracy: 0.0001)
    }

    func testProgressWithinChapterInterpolates() {
        let weights = [900, 40, 30, 30]   // total 1000
        // Halfway into the 40-char chapter 1: (900 + 20) / 1000 = 0.92.
        let progress = ReadingProgressMath.bookProgress(weights: weights, chapterIndex: 1, scrollFraction: 0.5)
        XCTAssertEqual(progress, 0.92, accuracy: 0.0001)
    }

    func testProgressClampsToUnitRange() {
        let weights = [100, 100]
        XCTAssertEqual(ReadingProgressMath.bookProgress(weights: weights, chapterIndex: 1, scrollFraction: 2.0), 1.0, accuracy: 0.0001)
        XCTAssertEqual(ReadingProgressMath.bookProgress(weights: weights, chapterIndex: 0, scrollFraction: -1.0), 0.0, accuracy: 0.0001)
    }

    func testEmptyWeightsFallBackToUniformByChapter() {
        // No weights computed yet (empty) — still gives a sane chapter-based guess.
        let progress = ReadingProgressMath.bookProgress(weights: [], chapterIndex: 0, scrollFraction: 0.5)
        XCTAssertEqual(progress, 0.5, accuracy: 0.0001)
    }

    func testMinutesRemainingAtStartApproximatesWholeBook() {
        // 22_000 chars ≈ 4000 words at 5.5 c/w ≈ 18 min at 220 wpm.
        let weights = [22_000]
        let minutes = ReadingProgressMath.minutesRemaining(weights: weights, chapterIndex: 0, scrollFraction: 0)
        XCTAssertEqual(minutes, 18)
    }

    func testMinutesRemainingIsZeroWhenFinished() {
        let weights = [1000, 1000]
        let minutes = ReadingProgressMath.minutesRemaining(weights: weights, chapterIndex: 1, scrollFraction: 1.0)
        XCTAssertEqual(minutes, 0)
    }

    func testMinutesRemainingHalfway() {
        // Halfway through: half the words remain.
        let weights = [22_000]
        let full = ReadingProgressMath.minutesRemaining(weights: weights, chapterIndex: 0, scrollFraction: 0)
        let half = ReadingProgressMath.minutesRemaining(weights: weights, chapterIndex: 0, scrollFraction: 0.5)
        XCTAssertEqual(half, Int((Double(full) / 2).rounded()), "roughly half the time remains at the midpoint")
    }
}
