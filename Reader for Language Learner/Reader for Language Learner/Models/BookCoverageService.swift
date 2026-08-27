//
//  BookCoverageService.swift
//  Reader for Language Learner
//
//  Whole-book vocabulary coverage (Roadmap v10 Sprint 2, L-V2).
//
//  `LexicalProfileService` answers "how much of this page do I know"; this
//  answers it for the book, which is the number worth showing on a library
//  card before you commit to reading something. The pass costs about a second
//  on a 277-page PDF, so it runs on a detached task when the book is opened
//  and only when the stored snapshot has actually gone stale — a new study
//  language, or saved words added or removed since.
//

import Foundation
import PDFKit

@MainActor
@Observable
final class BookCoverageService {

    /// Path of the book currently being profiled, for a progress affordance.
    private(set) var computingPath: String?

    @ObservationIgnored private var task: Task<Void, Never>?

    /// Profiles `url` against the reader's vocabulary unless `existing` is
    /// still good for it. `onComputed` runs on the main actor with a snapshot
    /// worth persisting.
    ///
    /// - Parameter epubDocument: the open book, for EPUBs. `EPUBDocument` is
    ///   `Sendable` and its chapter text is safe to pull from another task, so
    ///   the reader's own copy is reused rather than re-parsing the archive.
    func refreshIfNeeded(
        url: URL,
        epubDocument: EPUBDocument?,
        existing: BookCoverage?,
        language: Language,
        savedWordsStore: SavedWordsStore,
        onComputed: @MainActor @escaping (BookCoverage) -> Void
    ) {
        let fingerprint = savedWordsStore.vocabularyFingerprint(for: language)
        if let existing, existing.isFresh(language: language, fingerprint: fingerprint) { return }

        let keys = savedWordsStore.lemmaKeySets(for: language)
        guard !keys.mastered.isEmpty || !keys.learning.isEmpty else { return }

        task?.cancel()
        computingPath = url.path
        task = Task { [weak self] in
            let profile = await Task.detached(priority: .utility) {
                Self.profile(
                    url: url,
                    epubDocument: epubDocument,
                    language: language,
                    masteredKeys: keys.mastered,
                    learningKeys: keys.learning
                )
            }.value

            guard let self, !Task.isCancelled else { return }
            self.computingPath = nil
            guard let profile, profile.totalTokens > 0 else { return }
            onComputed(
                BookCoverage(
                    profile: profile,
                    language: language.rawValue,
                    vocabularyFingerprint: fingerprint,
                    computedAt: Date()
                )
            )
        }
    }

    // MARK: - Off-main pass

    /// Page by page (or chapter by chapter) rather than one call over the
    /// whole book: the counts add up either way, and this stays cancellable
    /// and doesn't hand the tagger a megabyte of text at once.
    private nonisolated static func profile(
        url: URL,
        epubDocument: EPUBDocument?,
        language: Language,
        masteredKeys: Set<String>,
        learningKeys: Set<String>
    ) -> LexicalProfile? {
        var total = LexicalProfile.empty

        for passage in passages(url: url, epubDocument: epubDocument) {
            if Task.isCancelled { return nil }
            guard !passage.isEmpty else { continue }
            total = total.adding(
                LexicalProfileBuilder.profile(
                    text: passage,
                    language: language,
                    masteredKeys: masteredKeys,
                    learningKeys: learningKeys
                )
            )
        }
        return total
    }

    private nonisolated static func passages(url: URL, epubDocument: EPUBDocument?) -> [String] {
        if let epubDocument {
            return epubDocument.spinePaths.indices.map { epubDocument.plainText(at: $0) }
        }
        if url.pathExtension.lowercased() == "epub" {
            guard let document = try? EPUBDocument(url: url) else { return [] }
            return document.spinePaths.indices.map { document.plainText(at: $0) }
        }
        // A fresh PDFDocument rather than the reader's: PDFKit objects belong
        // to the actor that opened them, and this runs off-main.
        guard let document = PDFDocument(url: url) else { return [] }
        return (0..<document.pageCount).compactMap { document.page(at: $0)?.string }
    }
}
