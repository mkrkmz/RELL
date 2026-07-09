//
//  PageAnalysisService.swift
//  Reader for Language Learner
//
//  Opt-in background vocabulary warming: pick candidate content words out of
//  the visible page/chapter text and pre-fetch their definitions into
//  QuickLookupService's cache, so a later hover/lookup is instant. Off by
//  default — callers gate every invocation behind the "pageAnalysisEnabled"
//  AppStorage toggle so a disabled toggle produces zero LLM traffic.
//

import Foundation
import NaturalLanguage

@MainActor
@Observable
final class PageAnalysisService {

    @ObservationIgnored private var currentTask: Task<Void, Never>?

    /// Cancels any in-flight warming and starts a new low-priority pass over
    /// `text`'s candidate words. Skips words already cached or saved, and
    /// warms sequentially (never floods the shared local-request gate).
    func analyze(text: String, savedWordsStore: SavedWordsStore, quickLookup: QuickLookupService) {
        currentTask?.cancel()
        let savedTerms = savedWordsStore.words.map(\.term)
        let candidates = Self.candidateWords(from: text, excluding: savedTerms)
        guard !candidates.isEmpty else { return }

        currentTask = Task(priority: .background) { [weak quickLookup] in
            for term in candidates {
                guard !Task.isCancelled, let quickLookup else { return }
                guard quickLookup.cachedDefinition(for: term, savedWordsStore: nil) == nil else { continue }
                _ = try? await quickLookup.definition(for: term)
            }
        }
    }

    func cancel() {
        currentTask?.cancel()
    }

    // MARK: - Candidate extraction

    /// Content words (noun/verb/adjective) worth pre-warming — lexical-class
    /// tagging naturally filters out pronouns, determiners, prepositions,
    /// etc. without a hand-maintained stopword list.
    nonisolated static func candidateWords(from text: String, excluding savedTerms: [String] = [], limit: Int = 6) -> [String] {
        guard !text.isEmpty else { return [] }
        let excluded = Set(savedTerms.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })

        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text

        var seen = Set<String>()
        var results: [String] = []
        let contentTags: Set<NLTag> = [.noun, .verb, .adjective]

        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitWhitespace, .omitPunctuation, .omitOther]
        ) { tag, range in
            if let tag, contentTags.contains(tag) {
                let word = text[range]
                if word.count >= 5, word.allSatisfy({ $0.isLetter }) {
                    let key = word.lowercased()
                    if !excluded.contains(key), !seen.contains(key) {
                        seen.insert(key)
                        results.append(String(word))
                    }
                }
            }
            return results.count < limit
        }

        return results
    }
}
