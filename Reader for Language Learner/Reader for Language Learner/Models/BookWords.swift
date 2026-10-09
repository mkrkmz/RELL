//
//  BookWords.swift
//  Reader for Language Learner
//
//  A book's words for its sidebar (Roadmap v16 Sprint 1, approved decision
//  1): the ones saved from it — from this file, another copy of the book or
//  a Kindle, matched by title (`BookIdentity`) — and, apart, the ones saved
//  elsewhere and met again in it. Pure, and cheap to recompute: a library
//  has a few dozen distinct source names, so each is matched once.
//

import Foundation

struct BookWords {
    /// Where the book's saved words came from — the merge menu lists them.
    struct Source: Identifiable, Equatable {
        enum Kind: Equatable { case thisFile, kindle, otherCopy }
        let kind: Kind
        /// The source's own name (a file name or a Kindle title).
        let name: String
        let count: Int
        var id: String { "\(kind)|\(name)" }
    }

    let saved: [SavedWord]
    /// Saved elsewhere, met again in this book.
    let met: [SavedWord]
    let sources: [Source]

    var ids: Set<UUID> { Set(saved.map(\.id)) }

    init(document: BookIdentity.Document, words: [SavedWord], encounters: [WordEncounter], matchingTitles: Bool) {
        var verdicts: [String: Bool] = [:]
        func matches(_ name: String) -> Bool {
            if let verdict = verdicts[name] { return verdict }
            let verdict = document.names.contains(name)
                || (matchingTitles && document.names.contains { BookIdentity.sameBook(name, $0) })
            verdicts[name] = verdict
            return verdict
        }
        func isThisFile(_ word: SavedWord) -> Bool {
            (word.documentPath != nil && word.documentPath == document.path)
                || word.pdfFilename.map(document.names.contains) == true
        }

        let saved = words.filter { word in
            isThisFile(word) || (word.pdfFilename.map(matches) ?? false)
        }
        let savedIDs = Set(saved.map(\.id))
        let metIDs = Set(encounters.filter { encounter in
            encounter.documentPath == document.path || (matchingTitles && matches(encounter.documentTitle))
        }.map(\.wordID)).subtracting(savedIDs)

        self.saved = saved
        self.met = words.filter { metIDs.contains($0.id) }

        var counts: [String: (Source.Kind, Int)] = [:]
        for word in saved {
            let name = word.pdfFilename ?? ""
            let kind: Source.Kind = isThisFile(word) ? .thisFile
                : word.hasTag(KindleVocabulary.deckName) ? .kindle : .otherCopy
            let key = kind == .thisFile ? "" : name
            counts[key] = (kind, (counts[key]?.1 ?? 0) + 1)
        }
        self.sources = counts
            .map { Source(kind: $0.value.0, name: $0.key, count: $0.value.1) }
            .sorted { ($0.count, $1.name) > ($1.count, $0.name) }
    }

    // MARK: The per-book switch (decision 2)

    /// Whether this book's words include other copies and Kindle, matched
    /// by title. On unless switched off for the book.
    static func matchesTitles(forDocumentAt path: String?, defaults: UserDefaults = .standard) -> Bool {
        guard let path else { return true }
        return !(defaults.stringArray(forKey: StorageKey.bookTitleMatchingOff) ?? []).contains(path)
    }

    static func setMatchesTitles(_ on: Bool, forDocumentAt path: String, defaults: UserDefaults = .standard) {
        var off = Set(defaults.stringArray(forKey: StorageKey.bookTitleMatchingOff) ?? [])
        if on { off.remove(path) } else { off.insert(path) }
        defaults.set(off.sorted(), forKey: StorageKey.bookTitleMatchingOff)
    }
}
