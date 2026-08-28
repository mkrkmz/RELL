//
//  EPUBGestureMathTests.swift
//  Reader for Language LearnerTests
//
//  The thresholds that decide whether a trackpad gesture reads as deliberate
//  (v10 Sprint 3, U-X3 and U-X4).
//

import XCTest
@testable import Reader_for_Language_Learner

final class PinchFontSizerTests: XCTestCase {

    private let step = PinchFontSizer.travelPerPoint

    func testSmallPinchDoesNotMoveTheSizeYet() {
        var sizer = PinchFontSizer()
        XCTAssertNil(sizer.size(after: step / 3, from: 18))
    }

    /// A slow pinch still moves: the leftover travel carries between events.
    func testTravelAccumulatesAcrossEvents() {
        var sizer = PinchFontSizer()
        XCTAssertNil(sizer.size(after: step / 2, from: 18))
        XCTAssertEqual(sizer.size(after: step / 2, from: 18), 19)
    }

    func testPinchOutGrowsAndPinchInShrinks() {
        var sizer = PinchFontSizer()
        XCTAssertEqual(sizer.size(after: step, from: 18), 19)
        sizer.reset()
        XCTAssertEqual(sizer.size(after: -step, from: 18), 17)
    }

    func testFastPinchMovesSeveralPointsAtOnce() {
        var sizer = PinchFontSizer()
        XCTAssertEqual(sizer.size(after: step * 3, from: 18), 21)
    }

    func testSizeClampsToTheReadingRange() {
        var sizer = PinchFontSizer()
        XCTAssertEqual(sizer.size(after: step * 40, from: 18), EPUBTypography.maxFontSize)
        sizer.reset()
        XCTAssertEqual(sizer.size(after: -step * 40, from: 18), EPUBTypography.minFontSize)
    }

    /// Already at the end of the range: nothing to report, so the caller
    /// doesn't write the same value back on every event.
    func testNoReportWhenAlreadyAtTheLimit() {
        var sizer = PinchFontSizer()
        XCTAssertNil(sizer.size(after: step * 5, from: EPUBTypography.maxFontSize))
        sizer.reset()
        XCTAssertNil(sizer.size(after: -step * 5, from: EPUBTypography.minFontSize))
    }

    func testResetDropsLeftoverTravel() {
        var sizer = PinchFontSizer()
        _ = sizer.size(after: step * 0.9, from: 18)
        sizer.reset()
        XCTAssertNil(sizer.size(after: step * 0.5, from: 18))
    }
}

final class SwipeChapterDetectorTests: XCTestCase {

    private let threshold = SwipeChapterDetector.threshold

    func testShortSwipeIsNotAChapterTurn() {
        var detector = SwipeChapterDetector()
        XCTAssertNil(detector.direction(deltaX: -threshold / 3, deltaY: 0))
    }

    func testSwipeLeftGoesToTheNextChapter() {
        var detector = SwipeChapterDetector()
        XCTAssertEqual(detector.direction(deltaX: -threshold, deltaY: 0), 1)
    }

    func testSwipeRightGoesToThePreviousChapter() {
        var detector = SwipeChapterDetector()
        XCTAssertEqual(detector.direction(deltaX: threshold, deltaY: 0), -1)
    }

    func testTravelAccumulatesAcrossEvents() {
        var detector = SwipeChapterDetector()
        XCTAssertNil(detector.direction(deltaX: -threshold / 2, deltaY: 0))
        XCTAssertEqual(detector.direction(deltaX: -threshold / 2 - 1, deltaY: 0), 1)
    }

    /// Scrolling the page diagonally is still scrolling.
    func testVerticallyDominantScrollIsIgnored() {
        var detector = SwipeChapterDetector()
        XCTAssertNil(detector.direction(deltaX: -threshold * 2, deltaY: -threshold * 3))
        XCTAssertFalse(detector.hasFired)
    }

    /// One chapter per gesture — a long swipe must not run through the book.
    func testFiresOnlyOncePerGesture() {
        var detector = SwipeChapterDetector()
        XCTAssertEqual(detector.direction(deltaX: -threshold, deltaY: 0), 1)
        XCTAssertNil(detector.direction(deltaX: -threshold, deltaY: 0))
        XCTAssertTrue(detector.hasFired)
    }

    func testResetStartsAFreshGesture() {
        var detector = SwipeChapterDetector()
        _ = detector.direction(deltaX: -threshold, deltaY: 0)
        detector.reset()
        XCTAssertFalse(detector.hasFired)
        XCTAssertEqual(detector.direction(deltaX: threshold, deltaY: 0), -1)
    }

    /// A wobble that changes its mind shouldn't add up to a swipe.
    func testOppositeTravelCancelsOut() {
        var detector = SwipeChapterDetector()
        XCTAssertNil(detector.direction(deltaX: -threshold * 0.8, deltaY: 0))
        XCTAssertNil(detector.direction(deltaX: threshold * 0.8, deltaY: 0))
        XCTAssertFalse(detector.hasFired)
    }
}
