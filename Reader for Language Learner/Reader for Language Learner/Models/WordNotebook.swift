//
//  WordNotebook.swift
//  Reader for Language Learner
//
//  What the word notebook's first column offers (Roadmap v16 Sprint 2):
//  every word, the ones waiting, new, forgotten often or without a meaning;
//  each book — its names gathered by title, so Kindle's "Why We Sleep" and
//  two downloaded copies are one row — and each deck. Pure.
//

import Foundation

enum WordNotebook {

    static let windowID = "words"

    /// A book in the notebook: every name its words were saved under.
    struct Book: Hashable, Identifiable {
        let names: [String]
        let title: String
        let count: Int
        var id: String { names.sorted().joined(separator: "|") }
    }

    enum Source: Hashable {
        case all, waiting, new, struggling, missingMeaning
        /// The same word saved twice (v16 S3).
        case duplicates
        case book(Book)
        case noBook
        case deck(String)
    }

    /// The books, most words first. Names are gathered by title
    /// (`BookIdentity.sameBook`); the shortest name is the row's title.
    static func books(from words: [SavedWord]) -> [Book] {
        var counts: [String: Int] = [:]
        for word in words {
            guard let name = word.pdfFilename, !name.isEmpty else { continue }
            counts[name, default: 0] += 1
        }
        var groups: [[String]] = []
        for name in counts.keys.sorted() {
            if let index = groups.firstIndex(where: { group in group.contains { BookIdentity.sameBook($0, name) } }) {
                groups[index].append(name)
            } else {
                groups.append([name])
            }
        }
        return groups
            .map { names in
                let title = names.min { BookIdentity.words($0).count < BookIdentity.words($1).count } ?? names[0]
                return Book(names: names, title: BookIdentity.displayTitle(title),
                            count: names.reduce(0) { $0 + (counts[$1] ?? 0) })
            }
            .sorted { ($0.count, $1.title) > ($1.count, $0.title) }
    }

    static func words(for source: Source, from words: [SavedWord], at now: Date = Date()) -> [SavedWord] {
        switch source {
        case .all:            return words
        case .waiting:        return words.filter { $0.hasBeenReviewed && $0.isDue(at: now) }
        case .new:            return words.filter { !$0.hasBeenReviewed }
        case .struggling:     return words.filter(\.isStruggling)
        case .missingMeaning: return words.filter { FillField.meaning.isMissing(in: $0) }
        case .duplicates:     return WordMerge.duplicates(in: words).flatMap(\.words)
        case .book(let book):
            let names = Set(book.names)
            return words.filter { $0.pdfFilename.map(names.contains) ?? false }
        case .noBook:         return words.filter { ($0.pdfFilename ?? "").isEmpty }
        case .deck(let tag):  return words.filter { $0.hasTag(tag) }
        }
    }

    // MARK: Opening on a word

    /// A word to show once the notebook is up — set before opening it, so a
    /// window that's only now appearing finds it.
    @MainActor static var pendingReveal: UUID?

    /// A book to show once the notebook is up — a library card's word count.
    @MainActor static var pendingBookName: String?

    /// Opens the notebook on the book saved under `name` (any of its names).
    @MainActor
    static func open(onBookNamed name: String, using openWindow: (String) -> Void) {
        pendingBookName = name
        openWindow(windowID)
        NotificationCenter.default.post(name: .revealInNotebook, object: nil)
    }

    /// The notebook's book for `name`: the one holding that name, or the
    /// same book by title.
    static func book(named name: String, in books: [Book]) -> Book? {
        books.first { $0.names.contains(name) } ?? books.first { $0.names.contains { BookIdentity.sameBook($0, name) } }
    }

    /// Opens the notebook on `id` (Spotlight, ⌘K, a book's "All Words…").
    @MainActor
    static func open(on id: UUID? = nil, using openWindow: (String) -> Void) {
        pendingReveal = id
        openWindow(windowID)
        if id != nil { NotificationCenter.default.post(name: .revealInNotebook, object: nil) }
    }
}

extension Notification.Name {
    nonisolated static let revealInNotebook = Notification.Name("revealInNotebook")
}
