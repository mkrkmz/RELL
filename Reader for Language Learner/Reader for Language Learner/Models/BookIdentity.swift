//
//  BookIdentity.swift
//  Reader for Language Learner
//
//  "Which book is this word from?" in one place (Roadmap v16 Sprint 0).
//  A saved word knows its book only by a name: the file name it was saved
//  from (`SavedWord.pdfFilename`) or, from a Kindle, the book's title. The
//  same book turns up under many names — on the user's Mac, "Why We Sleep"
//  (Kindle), "Matthew Walker PhD - Why We Sleep_ Unlocking the Power of
//  Sleep and Dreams-Scribner (2017)" (a PDF) and "Why We Sleep_ Unlocking
//  the Power of Sleep and Dreams -- Walker, Matthew -- 2215bb… -- Anna's
//  Archive" (an EPUB). Exact file names kept them apart; approved v16
//  decision 2 matches them by title.
//
//  The rule: reduce both names to words (dropping download-site tails,
//  years, copy numbers, "PhD"); they are the same book when the shorter
//  one's words appear, in order and together, in the longer one. A name of
//  one word only matches exactly — "science.aeg0769" shouldn't find every
//  science paper — and a "title" too long to be one (a story whose whole
//  text became its title) only matches exactly too.
//

import Foundation

enum BookIdentity {

    /// Above this many words a name isn't a title.
    static let longestTitle = 30

    /// A name as comparable words.
    static func words(_ name: String) -> [String] {
        var text = name.lowercased()
        // Download-site tails: "Title -- Author -- hash -- Anna's Archive".
        if let range = text.range(of: " -- ") { text = String(text[..<range.lowerBound]) }
        text = text.replacingOccurrences(of: "_", with: " ")
        // "(2017)", "(1)", "[epub]".
        text = text.replacingOccurrences(of: #"\(\s*\d{1,4}\s*\)|\[[^\]]*\]"#, with: " ", options: .regularExpression)
        let noise: Set<String> = ["phd", "dr", "epub", "pdf"]
        return text
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !noise.contains($0) }
    }

    /// Whether two names are the same book.
    static func sameBook(_ a: String, _ b: String) -> Bool {
        let left = words(a), right = words(b)
        guard !left.isEmpty, !right.isEmpty else { return false }
        if left == right { return true }
        let (short, long) = left.count <= right.count ? (left, right) : (right, left)
        guard short.count >= 2, long.count <= longestTitle else { return false }
        return contains(long, short)
    }

    /// `part` appears in `whole`, in order and together.
    private static func contains(_ whole: [String], _ part: [String]) -> Bool {
        guard part.count <= whole.count else { return false }
        for start in 0...(whole.count - part.count) where whole[start] == part[0] {
            if Array(whole[start..<(start + part.count)]) == part { return true }
        }
        return false
    }

    // MARK: Documents

    /// A document as the reader knows it: its file, and the names it goes by
    /// (file name, and the book's own title when it has one).
    struct Document: Equatable {
        var path: String?
        var names: [String]

        init(path: String?, names: [String]) {
            self.path = path
            self.names = names.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }

        /// A file on disk: its name without the extension, plus `title`.
        init(url: URL, title: String? = nil) {
            self.init(path: url.path, names: [url.deletingPathExtension().lastPathComponent] + (title.map { [$0] } ?? []))
        }
    }

    /// Whether `word` was saved from `document`: by the file it was saved
    /// from when it knows it, else by name — exactly, or by title when
    /// `matchingTitles` (the per-book switch, decision 2).
    static func isSaved(_ word: SavedWord, in document: Document, matchingTitles: Bool = true) -> Bool {
        // The file first; a moved or renamed file falls back to its name.
        if let path = word.documentPath, path == document.path { return true }
        guard let source = word.pdfFilename else { return false }
        if document.names.contains(source) { return true }
        return matchingTitles && document.names.contains { sameBook(source, $0) }
    }

    /// Whether an encounter happened in `document`.
    static func isMet(_ encounter: WordEncounter, in document: Document, matchingTitles: Bool = true) -> Bool {
        if encounter.documentPath == document.path { return true }
        return matchingTitles && document.names.contains { sameBook(encounter.documentTitle, $0) }
    }
}
