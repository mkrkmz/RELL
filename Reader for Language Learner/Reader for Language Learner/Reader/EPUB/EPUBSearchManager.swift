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

    /// Bumped on every `runSearch` call; a chapter result only gets applied
    /// if its generation still matches, so a stale detached task that's
    /// already mid-scan when a newer search starts can't clobber it.
    private var searchGeneration = 0
    /// Exposed (not `private`) so tests can `await` it — otherwise there's
    /// no way to observe completion of the detached background scan.
    private(set) var currentSearchTask: Task<Void, Never>?

    var totalMatches: Int { results.reduce(0) { $0 + $1.matchCount } }

    func showFindBar() {
        isFindBarVisible = true
    }

    func closeFindBar() {
        isFindBarVisible = false
        clear()
    }

    func clear() {
        currentSearchTask?.cancel()
        searchGeneration += 1
        query = ""
        results = []
        hasSearched = false
    }

    /// Case-insensitive scan across all chapters, chapter-by-chapter on a
    /// detached background task — a long book's full text shouldn't block
    /// the main thread — publishing each chapter's result to `results` as
    /// soon as it's found so the list fills in incrementally rather than
    /// appearing all at once at the end. Starting a new search cancels
    /// whatever scan is already in flight.
    func runSearch(in document: EPUBDocument) {
        currentSearchTask?.cancel()

        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.count >= 2 else {
            searchGeneration += 1
            results = []
            hasSearched = false
            return
        }

        searchGeneration += 1
        let generation = searchGeneration
        results = []
        hasSearched = true

        currentSearchTask = Task.detached(priority: .userInitiated) { [weak self] in
            for index in 0..<document.chapterCount {
                if Task.isCancelled { return }
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
                let result = EPUBSearchResult(
                    chapterIndex: index,
                    chapterTitle: document.chapterTitle(at: index),
                    matchCount: count,
                    snippet: Self.snippet(around: firstRange, in: text)
                )

                await MainActor.run {
                    guard let self, self.searchGeneration == generation else { return }
                    self.results.append(result)
                }
            }
        }
    }

    /// `nonisolated` — pure string slicing, called from the detached scan
    /// task; without this it would inherit the enclosing class's `@MainActor`
    /// and force a hop back to the main thread for every match found.
    private nonisolated static func snippet(around range: Range<String.Index>, in text: String) -> String {
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
