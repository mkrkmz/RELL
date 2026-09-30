//
//  WordPageModel.swift
//  Reader for Language Learner
//
//  The pure half of the word page (Roadmap v13 Sprint 1): how well a word is
//  remembered right now, and the reading history summed up in one line.
//

import Foundation
import SwiftUI

enum WordPageModel {

    /// Probability of recalling the word now, 0…1, from its FSRS stability
    /// and time since the last review. nil before the first review — there
    /// is nothing to estimate from.
    static func recallNow(_ word: SavedWord, now: Date = Date()) -> Double? {
        guard let stability = word.stability, stability > 0,
              let last = word.lastReviewedAt
        else { return nil }
        let days = now.timeIntervalSince(last) / 86_400
        return FSRSScheduler.retrievability(elapsedDays: days, stability: stability)
    }

    /// "Met 7 times in 3 books" — occurrences on every logged page, not just
    /// the number of pages.
    static func encounterSummary(_ encounters: [WordEncounter]) -> String? {
        guard !encounters.isEmpty else { return nil }
        let times = encounters.reduce(0) { $0 + max(1, $1.occurrences) }
        let books = Set(encounters.map(\.documentPath)).count
        // Spelled out rather than one "%lld … %lld" string: English needs the
        // singulars, and "Met 1 times in 1 documents" was the result.
        if books == 1 {
            return times == 1
                ? String(localized: "Met once")
                : String(localized: "Met \(times) times in one document")
        }
        return String(localized: "Met \(times) times in \(books) documents")
    }

    /// "p. 12" / "Chapter 8" — 1-based for people.
    static func locationLabel(_ encounter: WordEncounter) -> String {
        encounter.isEPUB
            ? String(localized: "Chapter \(encounter.location + 1)")
            : String(localized: "p. \(encounter.location + 1)")
    }

    /// The sentence with the word — in whatever form it takes there — in bold.
    static func emphasized(_ sentence: String, term: String, language: Language?) -> AttributedString {
        var result = AttributedString(sentence)
        var needles = [term]
        let keys: Set<String> = [
            term.lowercased(),
            LemmaMatcher.matchKey(for: term, language: language),
        ]
        needles += LemmaMatcher.surfaceForms(in: sentence, matchingKeys: keys, language: language)

        let nsSentence = sentence as NSString
        for needle in Set(needles.map { $0.lowercased() }) {
            for range in TermMatcher.ranges(of: needle, in: nsSentence) {
                guard let swiftRange = Range(range, in: sentence),
                      let lower = AttributedString.Index(swiftRange.lowerBound, within: result),
                      let upper = AttributedString.Index(swiftRange.upperBound, within: result)
                else { continue }
                result[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
            }
        }
        return result
    }
}
