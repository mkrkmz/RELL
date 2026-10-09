//
//  WordMerge.swift
//  Reader for Language Learner
//
//  The same word saved twice — "gleaming" and "gleam", "Lolled" and "loll"
//  (Roadmap v16 Sprint 3). The word notebook lists them; merging, after you
//  confirm, keeps one with everything both had: sentences, decks, notes,
//  filled fields and the whole review history, and the memory state of the
//  one you knew better. Pure.
//

import Foundation

enum WordMerge {

    struct Group: Identifiable, Equatable {
        /// The words, the one to keep by default first.
        let words: [SavedWord]
        var id: String { words.map(\.id.uuidString).sorted().joined(separator: "|") }
    }

    /// Words sharing a dictionary form in the same language. `lemma` is the
    /// tagger (injected: tests and the real one differ by machine).
    static func duplicates(
        in words: [SavedWord],
        lemma: (String, Language?) -> String? = { LemmaMatcher.lemma(of: $0, language: $1) }
    ) -> [Group] {
        var buckets: [String: [SavedWord]] = [:]
        for word in words {
            let language = word.language.flatMap(Language.init(rawValue:))
            let term = word.term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !term.isEmpty else { continue }
            let key = (language?.rawValue ?? "") + "|" + (lemma(term, language) ?? term)
            buckets[key, default: []].append(word)
        }
        return buckets.values
            .filter { $0.count > 1 }
            .map { Group(words: $0.sorted(by: preferredToKeep)) }
            .sorted { $0.words[0].term.localizedCaseInsensitiveCompare($1.words[0].term) == .orderedAscending }
    }

    /// The one to keep unless you pick another: the most reviewed, then the
    /// oldest.
    static func preferredToKeep(_ a: SavedWord, _ b: SavedWord) -> Bool {
        if a.reviewCount != b.reviewCount { return a.reviewCount > b.reviewCount }
        return a.savedAt < b.savedAt
    }

    /// `keep` with what `others` add.
    static func merged(keep: SavedWord, others: [SavedWord]) -> SavedWord {
        var word = keep
        let all = [keep] + others

        // Card fields: fill what's empty, with the source mark it came with.
        for other in others {
            for (key, value) in other.llmOutputs
            where (word.llmOutputs[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                word.llmOutputs[key] = value
                if let field = FillField.allCases.first(where: { $0.module?.rawValue == key }),
                   let source = other.fieldSources[field.rawValue] {
                    word.fieldSources[field.rawValue] = source
                }
            }
            if word.cefrLevel == nil, let level = other.cefrLevel {
                word.cefrLevel = level
                word.cefrIsAuto = other.cefrIsAuto
                word.fieldSources[FillField.level.rawValue] = other.fieldSources[FillField.level.rawValue]
            }
        }

        // Decks, once each.
        var seen = Set(word.tags.map { $0.lowercased() })
        for tag in others.flatMap(\.tags) where seen.insert(tag.lowercased()).inserted {
            word.tags.append(tag)
        }

        // Sentences: the kept one's stays; the others' go into the notes so
        // nothing read is lost.
        if word.sentence.isEmpty, let first = others.first(where: { !$0.sentence.isEmpty }) {
            word.sentence = first.sentence
        }
        var notes = word.notes.isEmpty ? [] : [word.notes]
        for other in others {
            if !other.notes.isEmpty { notes.append(other.notes) }
            if !other.sentence.isEmpty, other.sentence != word.sentence {
                notes.append(String(localized: "Also saved as “\(other.term)”: \(other.sentence)"))
            }
        }
        word.notes = notes.joined(separator: "\n\n")

        // The whole review history, and the memory of the better-known one.
        word.reviewEvents = Array(all.flatMap(\.reviewEvents).sorted { $0.date < $1.date }.suffix(500))
        word.reviewHistory = all.flatMap(\.reviewHistory).sorted()
        word.reviewCount = all.reduce(0) { $0 + $1.reviewCount }
        word.incorrectCount = all.reduce(0) { $0 + $1.incorrectCount }
        word.lastReviewedAt = all.compactMap(\.lastReviewedAt).max()
        if let best = all.max(by: { ($0.stability ?? -1) < ($1.stability ?? -1) }), best.stability != nil {
            word.stability = best.stability
            word.difficulty = best.difficulty
            word.nextReviewAt = best.nextReviewAt
            word.easeFactor = best.easeFactor
            word.masteryLevel = best.masteryLevel
        }
        word.savedAt = all.map(\.savedAt).min() ?? word.savedAt
        return word
    }
}
