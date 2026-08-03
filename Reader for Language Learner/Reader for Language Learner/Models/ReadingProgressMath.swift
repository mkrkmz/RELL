//
//  ReadingProgressMath.swift
//  Reader for Language Learner
//
//  Book-wide reading progress for reflowable EPUBs (Roadmap v9 Sprint 2, U3).
//  Chapters vary wildly in length, so counting "chapter N of M" misrepresents
//  how far through a book the reader actually is. These pure functions weight
//  progress by each chapter's content length and estimate the time left, so
//  the reader chrome can show an honest percentage and a "X min left".
//

import Foundation

enum ReadingProgressMath {
    /// Fraction (0…1) through the whole book, given each chapter's content
    /// weight (e.g. character count), the current chapter, and how far the
    /// reader has scrolled within it. Falls back to uniform chapter weighting
    /// when weights are unavailable.
    static func bookProgress(weights: [Int], chapterIndex: Int, scrollFraction: Double) -> Double {
        let fraction = min(max(scrollFraction, 0), 1)
        guard !weights.isEmpty, chapterIndex >= 0, chapterIndex < weights.count else {
            // No weights yet — approximate uniformly by chapter.
            let count = max(weights.count, 1)
            guard chapterIndex >= 0 else { return 0 }
            return min(1, (Double(chapterIndex) + fraction) / Double(count))
        }
        let total = weights.reduce(0, +)
        guard total > 0 else {
            return min(1, (Double(chapterIndex) + fraction) / Double(weights.count))
        }
        let before = weights[0..<chapterIndex].reduce(0, +)
        let within = Double(weights[chapterIndex]) * fraction
        return min(1, max(0, (Double(before) + within) / Double(total)))
    }

    /// Estimated minutes of reading left in the book. Content length →
    /// words (via average characters-per-word) → minutes (via reading speed).
    /// Returns 0 once effectively finished.
    static func minutesRemaining(
        weights: [Int],
        chapterIndex: Int,
        scrollFraction: Double,
        charactersPerWord: Double = 5.5,
        wordsPerMinute: Double = 220
    ) -> Int {
        guard !weights.isEmpty, wordsPerMinute > 0, charactersPerWord > 0 else { return 0 }
        let total = weights.reduce(0, +)
        guard total > 0 else { return 0 }
        let progress = bookProgress(weights: weights, chapterIndex: chapterIndex, scrollFraction: scrollFraction)
        let remainingChars = Double(total) * (1 - progress)
        let remainingWords = remainingChars / charactersPerWord
        return max(0, Int((remainingWords / wordsPerMinute).rounded()))
    }
}
