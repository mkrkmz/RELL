//
//  EPUBGestureMath.swift
//  Reader for Language Learner
//
//  Trackpad gesture arithmetic for the EPUB reader (Roadmap v10 Sprint 3,
//  U-X3 and U-X4). Kept out of the web view so the thresholds — the part
//  that decides whether a gesture feels deliberate or twitchy — can be
//  exercised without synthesizing NSEvents.
//

import CoreGraphics
import Foundation

/// Accumulates pinch magnification into whole points of reading font size.
///
/// A pinch arrives as a stream of small magnifications; stepping the size on
/// each one would race past the range in a single gesture. The remainder
/// carries between events so a slow pinch still moves, one point at a time.
struct PinchFontSizer {

    /// Pinch travel worth one point of font size.
    static let travelPerPoint: CGFloat = 0.08

    private var remainder: CGFloat = 0

    /// Call at the start and end of a gesture — leftover travel must not leak
    /// into the next pinch.
    mutating func reset() {
        remainder = 0
    }

    /// The new font size, or nil when this event doesn't move it: either the
    /// pinch hasn't travelled a full point yet, or the size is already at the
    /// end of its range.
    mutating func size(after magnification: CGFloat, from fontSize: Double) -> Double? {
        remainder += magnification
        let steps = (remainder / Self.travelPerPoint).rounded(.towardZero)
        guard steps != 0 else { return nil }
        remainder -= steps * Self.travelPerPoint

        let next = min(
            EPUBTypography.maxFontSize,
            max(EPUBTypography.minFontSize, fontSize + Double(steps))
        )
        return next == fontSize ? nil : next
    }
}

/// Decides when a two-finger scroll is a chapter-turning swipe.
///
/// Fires once per gesture: a chapter turn is a jump, and a long swipe that
/// kept reporting would run through the book. The caller resets on the
/// gesture's `began` phase and ignores momentum once it has fired.
struct SwipeChapterDetector {

    /// Horizontal travel that counts as a deliberate swipe.
    static let threshold: CGFloat = 55

    private var travel: CGFloat = 0
    private(set) var hasFired = false

    mutating func reset() {
        travel = 0
        hasFired = false
    }

    /// `+1` for the next chapter, `-1` for the previous one, nil while the
    /// gesture is still ambiguous, too short, or has already fired.
    ///
    /// Diagonal scrolling belongs to the page: an event only counts when it
    /// is dominantly horizontal.
    mutating func direction(deltaX: CGFloat, deltaY: CGFloat) -> Int? {
        guard !hasFired, abs(deltaX) > abs(deltaY) else { return nil }
        travel += deltaX
        guard abs(travel) >= Self.threshold else { return nil }
        hasFired = true
        // Natural scrolling: fingers left push the content left and reveal
        // what comes next, which arrives as a negative delta.
        return travel < 0 ? 1 : -1
    }
}
