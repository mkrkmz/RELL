//
//  EPUBGestureMathTests.swift
//  Reader for Language LearnerTests
//
//  The thresholds that decide whether a trackpad gesture reads as deliberate
//  (v10 Sprint 3, U-X3 and U-X4).
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class PinchFontSizerTests: XCTestCase {

    private let step = PinchFontSizer.travelPerPoint

    func testSmallPinchDoesNotMoveTheSizeYet() async {
        var sizer = PinchFontSizer()
        XCTAssertNil(sizer.size(after: step / 3, from: 18))
    }

    /// A slow pinch still moves: the leftover travel carries between events.
    func testTravelAccumulatesAcrossEvents() async {
        var sizer = PinchFontSizer()
        XCTAssertNil(sizer.size(after: step / 2, from: 18))
        XCTAssertEqual(sizer.size(after: step / 2, from: 18), 19)
    }

    func testPinchOutGrowsAndPinchInShrinks() async {
        var sizer = PinchFontSizer()
        XCTAssertEqual(sizer.size(after: step, from: 18), 19)
        sizer.reset()
        XCTAssertEqual(sizer.size(after: -step, from: 18), 17)
    }

    func testFastPinchMovesSeveralPointsAtOnce() async {
        var sizer = PinchFontSizer()
        XCTAssertEqual(sizer.size(after: step * 3, from: 18), 21)
    }

    func testSizeClampsToTheReadingRange() async {
        var sizer = PinchFontSizer()
        XCTAssertEqual(sizer.size(after: step * 40, from: 18), EPUBTypography.maxFontSize)
        sizer.reset()
        XCTAssertEqual(sizer.size(after: -step * 40, from: 18), EPUBTypography.minFontSize)
    }

    /// Already at the end of the range: nothing to report, so the caller
    /// doesn't write the same value back on every event.
    func testNoReportWhenAlreadyAtTheLimit() async {
        var sizer = PinchFontSizer()
        XCTAssertNil(sizer.size(after: step * 5, from: EPUBTypography.maxFontSize))
        sizer.reset()
        XCTAssertNil(sizer.size(after: -step * 5, from: EPUBTypography.minFontSize))
    }

    func testResetDropsLeftoverTravel() async {
        var sizer = PinchFontSizer()
        _ = sizer.size(after: step * 0.9, from: 18)
        sizer.reset()
        XCTAssertNil(sizer.size(after: step * 0.5, from: 18))
    }
}

@MainActor
final class SwipeChapterDetectorTests: XCTestCase {

    private let threshold = SwipeChapterDetector.threshold

    func testShortSwipeIsNotAChapterTurn() async {
        var detector = SwipeChapterDetector()
        XCTAssertNil(detector.direction(deltaX: -threshold / 3, deltaY: 0))
    }

    func testSwipeLeftGoesToTheNextChapter() async {
        var detector = SwipeChapterDetector()
        XCTAssertEqual(detector.direction(deltaX: -threshold, deltaY: 0), 1)
    }

    func testSwipeRightGoesToThePreviousChapter() async {
        var detector = SwipeChapterDetector()
        XCTAssertEqual(detector.direction(deltaX: threshold, deltaY: 0), -1)
    }

    func testTravelAccumulatesAcrossEvents() async {
        var detector = SwipeChapterDetector()
        XCTAssertNil(detector.direction(deltaX: -threshold / 2, deltaY: 0))
        XCTAssertEqual(detector.direction(deltaX: -threshold / 2 - 1, deltaY: 0), 1)
    }

    /// Scrolling the page diagonally is still scrolling.
    func testVerticallyDominantScrollIsIgnored() async {
        var detector = SwipeChapterDetector()
        XCTAssertNil(detector.direction(deltaX: -threshold * 2, deltaY: -threshold * 3))
        XCTAssertFalse(detector.hasFired)
    }

    /// One chapter per gesture — a long swipe must not run through the book.
    func testFiresOnlyOncePerGesture() async {
        var detector = SwipeChapterDetector()
        XCTAssertEqual(detector.direction(deltaX: -threshold, deltaY: 0), 1)
        XCTAssertNil(detector.direction(deltaX: -threshold, deltaY: 0))
        XCTAssertTrue(detector.hasFired)
    }

    func testResetStartsAFreshGesture() async {
        var detector = SwipeChapterDetector()
        _ = detector.direction(deltaX: -threshold, deltaY: 0)
        detector.reset()
        XCTAssertFalse(detector.hasFired)
        XCTAssertEqual(detector.direction(deltaX: threshold, deltaY: 0), -1)
    }

    /// A wobble that changes its mind shouldn't add up to a swipe.
    func testOppositeTravelCancelsOut() async {
        var detector = SwipeChapterDetector()
        XCTAssertNil(detector.direction(deltaX: -threshold * 0.8, deltaY: 0))
        XCTAssertNil(detector.direction(deltaX: threshold * 0.8, deltaY: 0))
        XCTAssertFalse(detector.hasFired)
    }
}
