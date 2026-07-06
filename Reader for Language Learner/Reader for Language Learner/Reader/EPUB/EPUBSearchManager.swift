//
//  EPUBSearchManager.swift
//  Reader for Language Learner
//
//  In-book search: scans the spine's plain text for per-chapter match
//  counts and snippets; in-page highlighting rides WKWebView's native
//  find. The EPUB counterpart of PDFSearchManager.
//

import Foundation
import Observation

struct EPUBSearchResult: Identifiable {
    let id = UUID()
    let chapterIndex: Int
    let chapterTitle: String
    let matchCount: Int
    /// Short context around the first match in the chapter.
    let snippet: String
}

@MainActor
@Observable
final class EPUBSearchManager {

    var query = ""
    private(set) var results: [EPUBSearchResult] = []
    private(set) var isFindBarVisible = false
    private(set) var hasSearched = false

    var totalMatches: Int { results.reduce(0) { $0 + $1.matchCount } }

    func showFindBar() {
        isFindBarVisible = true
    }

    func closeFindBar() {
        isFindBarVisible = false
        clear()
    }

    func clear() {
        query = ""
        results = []
        hasSearched = false
    }

    /// Case-insensitive scan across all chapters. Runs synchronously —
    /// EPUB text bodies are small (a novel ≈ 1 MB of text).
    func runSearch(in document: EPUBDocument) {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.count >= 2 else {
            results = []
            hasSearched = false
            return
        }

        var found: [EPUBSearchResult] = []
        for index in 0..<document.chapterCount {
            let text = document.plainText(at: index)
            guard !text.isEmpty else { continue }

            var count = 0
            var firstRange: Range<String.Index>?
            var searchStart = text.startIndex
            while let range = text.range(
                of: term, options: [.caseInsensitive, .diacriticInsensitive],
                range: searchStart..<text.endIndex
            ) {
                if firstRange == nil { firstRange = range }
                count += 1
                searchStart = range.upperBound
            }

            guard count > 0, let firstRange else { continue }
            found.append(EPUBSearchResult(
                chapterIndex: index,
                chapterTitle: document.chapterTitle(at: index),
                matchCount: count,
                snippet: Self.snippet(around: firstRange, in: text)
            ))
        }

        results = found
        hasSearched = true
    }

    private static func snippet(around range: Range<String.Index>, in text: String) -> String {
        let radius = 40
        let start = text.index(range.lowerBound, offsetBy: -radius, limitedBy: text.startIndex)
            ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: radius, limitedBy: text.endIndex)
            ?? text.endIndex
        let raw = text[start..<end]
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return "…\(raw)…"
    }
}
