//
//  TermMatcher.swift
//  Reader for Language Learner
//
//  Whole-word occurrence matching for saved-word highlighting. The EPUB
//  reader has done Unicode-aware boundary matching in JS since v1.15
//  (`rellFindTermRanges`); the PDF reader matched plain substrings, so a
//  saved "run" underlined the middle of "brunt". This is that same rule in
//  Swift, kept free of view state so both readers can agree and the rule
//  can be unit-tested.
//

import Foundation

enum TermMatcher {

    /// Scripts with no whitespace word segmentation: Hiragana/Katakana, CJK
    /// ideographs, Hangul syllables. A boundary check would reject every real
    /// match in these (the neighbouring character is itself a letter), so
    /// terms containing them fall back to a plain substring scan — the same
    /// exception the EPUB side makes.
    private static let unsegmentedScripts: [ClosedRange<UInt32>] = [
        0x3040...0x30FF, // Hiragana, Katakana
        0x3400...0x9FFF, // CJK Unified Ideographs (incl. Extension A)
        0xAC00...0xD7AF  // Hangul syllables
    ]

    /// False when the term is written in a script that has no word boundaries.
    static func usesWholeWordMatching(_ term: String) -> Bool {
        !term.unicodeScalars.contains { scalar in
            unsegmentedScripts.contains { $0.contains(scalar.value) }
        }
    }

    /// Ranges of every occurrence of `term` in `text`, case-insensitively.
    /// Matches are whole-word (letters, marks and digits may not sit directly
    /// against either end) unless the term's script has no such concept.
    ///
    /// `text` is an `NSString` because the callers work in UTF-16 offsets:
    /// PDFKit's `page.selection(for:)` and the EPUB DOM both do.
    static func ranges(of term: String, in text: NSString, limit: Int = .max) -> [NSRange] {
        let needle = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty, text.length > 0, limit > 0 else { return [] }

        let wholeWord = usesWholeWordMatching(needle)
        var ranges: [NSRange] = []
        var searchStart = 0

        while searchStart < text.length, ranges.count < limit {
            let scope = NSRange(location: searchStart, length: text.length - searchStart)
            let found = text.range(of: needle, options: .caseInsensitive, range: scope)
            guard found.location != NSNotFound else { break }

            if !wholeWord || isWholeWord(found, in: text) {
                ranges.append(found)
            }
            searchStart = found.location + max(found.length, 1)
        }
        return ranges
    }

    // MARK: - Boundaries

    private static func isWholeWord(_ range: NSRange, in text: NSString) -> Bool {
        !isWordScalar(scalar(endingBefore: range.location, in: text))
            && !isWordScalar(scalar(startingAt: range.location + range.length, in: text))
    }

    /// Letters, combining marks and digits — `\p{L}\p{N}` plus marks, so a
    /// match ending against a combining accent isn't treated as whole.
    private static func isWordScalar(_ scalar: Unicode.Scalar?) -> Bool {
        guard let scalar else { return false }
        return CharacterSet.alphanumerics.contains(scalar)
    }

    /// The scalar whose last UTF-16 unit sits at `index - 1`, nil at the start
    /// of the text. Surrogate pairs are recombined so an emoji or a rare CJK
    /// ideograph isn't read as a lone surrogate.
    private static func scalar(endingBefore index: Int, in text: NSString) -> Unicode.Scalar? {
        guard index > 0, index <= text.length else { return nil }
        let unit = text.character(at: index - 1)
        if UTF16.isTrailSurrogate(unit), index >= 2 {
            let lead = text.character(at: index - 2)
            if UTF16.isLeadSurrogate(lead) {
                return combine(lead: lead, trail: unit)
            }
        }
        return Unicode.Scalar(unit)
    }

    /// The scalar starting at `index`, nil at the end of the text.
    private static func scalar(startingAt index: Int, in text: NSString) -> Unicode.Scalar? {
        guard index >= 0, index < text.length else { return nil }
        let unit = text.character(at: index)
        if UTF16.isLeadSurrogate(unit), index + 1 < text.length {
            let trail = text.character(at: index + 1)
            if UTF16.isTrailSurrogate(trail) {
                return combine(lead: unit, trail: trail)
            }
        }
        return Unicode.Scalar(unit)
    }

    private static func combine(lead: unichar, trail: unichar) -> Unicode.Scalar? {
        let value = (UInt32(lead) - 0xD800) * 0x400 + (UInt32(trail) - 0xDC00) + 0x10000
        return Unicode.Scalar(value)
    }
}
