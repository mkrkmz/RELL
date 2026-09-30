//
//  CommandPalette.swift
//  Reader for Language Learner
//
//  ⌘K (Roadmap v13 Sprint 5): one search box over commands, the open
//  book's chapters, the library and saved words. The ranking here is pure;
//  the window supplies the items and what each one does.
//

import Foundation

struct PaletteItem: Identifiable {
    enum Kind: Int, CaseIterable {
        // Order breaks ties: a command beats a chapter beats a word beats a
        // document with the same match quality.
        case command, page, chapter, word, document
    }

    let id: String
    let kind: Kind
    let title: String
    var subtitle: String = ""
    var icon: String
    var isEnabled = true
    let perform: () -> Void
}

nonisolated enum PaletteMatcher {

    /// How well `query` matches `title`, higher is better; nil for no match.
    /// Whole-title prefix > word prefix > substring > letters in order.
    /// Case- and accent-insensitive, so "gune" finds "Güneş".
    static func score(_ query: String, _ title: String) -> Int? {
        let q = fold(query)
        guard !q.isEmpty else { return 0 }
        let t = fold(title)
        if t == q { return 1_000 }
        if t.hasPrefix(q) { return 900 - min(t.count, 200) }
        let words = t.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if words.contains(where: { $0.hasPrefix(q) }) { return 700 - min(t.count, 200) }
        if t.contains(q) { return 500 - min(t.count, 200) }
        // Letters in order ("zm" → "Zen Mode"), tighter spans score higher.
        var index = t.startIndex
        var first: String.Index?
        for character in q {
            guard let found = t[index...].firstIndex(of: character) else { return nil }
            if first == nil { first = found }
            index = t.index(after: found)
        }
        let span = t.distance(from: first ?? t.startIndex, to: index)
        return max(1, 300 - span * 5)
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Items matching `query`, best first; an empty query keeps the given
    /// order (commands first, as the window lists them).
    static func rank<Item>(
        _ items: [Item],
        query: String,
        title: (Item) -> String,
        kind: (Item) -> Int,
        limit: Int = 40
    ) -> [Item] {
        guard !fold(query).isEmpty else { return Array(items.prefix(limit)) }
        return items
            .compactMap { item in score(query, title(item)).map { (item, $0) } }
            .sorted { lhs, rhs in
                lhs.1 != rhs.1 ? lhs.1 > rhs.1 : kind(lhs.0) < kind(rhs.0)
            }
            .prefix(limit)
            .map(\.0)
    }

    /// "42" or "p 42" → page 42.
    static func pageNumber(in query: String) -> Int? {
        let digits = query.lowercased()
            .replacingOccurrences(of: "p", with: "")
            .replacingOccurrences(of: "s", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let number = Int(digits), number > 0 else { return nil }
        return number
    }
}
