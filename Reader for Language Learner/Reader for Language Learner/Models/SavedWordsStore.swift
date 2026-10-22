//
//  SavedWordsStore.swift
//  Reader for Language Learner
//

import Foundation
import os
import SwiftUI

enum ReviewRating: String, CaseIterable, Codable, Hashable, Identifiable {
    case again
    /// Recalled, but with effort. FSRS schedules it shorter than `good`.
    case hard
    case good
    case easy

    var id: String { rawValue }

    var label: String {
        switch self {
        case .again: return "Again"
        case .hard: return "Hard"
        case .good: return "Good"
        case .easy: return "Easy"
        }
    }

    /// Visible UI text goes through this — see CLAUDE.md's `Text(String)` note.
    var localizedTitle: String {
        switch self {
        case .again: return String(localized: "Again")
        case .hard: return String(localized: "Hard")
        case .good: return String(localized: "Good")
        case .easy: return String(localized: "Easy")
        }
    }

    var icon: String {
        switch self {
        case .again: return "arrow.counterclockwise"
        case .hard: return "tortoise"
        case .good: return "checkmark.circle"
        case .easy: return "checkmark.seal"
        }
    }

    /// FSRS's four-button scale.
    var fsrsGrade: FSRSGrade {
        switch self {
        case .again: return .again
        case .hard: return .hard
        case .good: return .good
        case .easy: return .easy
        }
    }
}

/// Manages persistence and CRUD for the user's saved vocabulary.
/// Stores data as a JSON file in Application Support.
@MainActor
@Observable
final class SavedWordsStore {
    /// Off the main actor: on macOS 15 a main-actor deinit run outside a
    /// task crashes when it releases another one (v16 S0, CI crash reports).
    nonisolated deinit {}

    struct ReviewActivityDay: Identifiable, Equatable {
        let date: Date
        let count: Int

        var id: Date { date }
    }

    /// One calendar week's review accuracy, plus the running ("lifetime so
    /// far") accuracy through that week — the stats panel's bars and
    /// retention trend line come from the same array.
    struct WeeklyAccuracy: Identifiable, Equatable {
        let weekStart: Date
        let correctCount: Int
        let incorrectCount: Int
        /// Running accuracy across every review from the beginning through
        /// the end of this week. `nil` before any review has ever happened.
        let cumulativeAccuracy: Double?

        var id: Date { weekStart }
        var totalCount: Int { correctCount + incorrectCount }
        /// `nil` for a week with no reviews at all — the chart should leave
        /// a gap there rather than draw a false 0%.
        var accuracy: Double? {
            totalCount > 0 ? Double(correctCount) / Double(totalCount) : nil
        }
    }

    struct LanguageWordCount: Identifiable, Equatable {
        let language: Language
        let count: Int
        var id: String { language.rawValue }
    }

    private(set) var words: [SavedWord] = []
    var saveError: String? = nil

    private let fileURL: URL
    private let writer: DebouncedFileWriter

    /// - Parameter customFileURL: test-only override; when present the store
    ///   writes through synchronously (debounce 0) so reload-from-disk
    ///   assertions stay deterministic. The app path debounces off-main.
    init(fileURL customFileURL: URL? = nil) {
        let resolved = DebouncedFileWriter.forAppSupport(
            filename: "saved_words.json",
            storeName: "SavedWordsStore",
            customFileURL: customFileURL
        )
        self.fileURL = resolved.url
        self.writer = resolved.writer
        self.words = resolved.canLoad ? Self.load(from: resolved.url) : []
        writer.onResult = { [weak self] error in self?.saveError = error }
        if resolved.canLoad {
            backfillMissingLanguage()
        }
    }

    /// One-time migration for pre-v1.24 words, which have no `language`.
    /// Filling it at load time (not read time) means a later target-language
    /// change won't silently relabel words that were already saved.
    private func backfillMissingLanguage() {
        guard words.contains(where: { $0.language == nil }) else { return }
        let target = Language.storedTarget.rawValue
        for index in words.indices where words[index].language == nil {
            words[index].language = target
        }
        save()
    }

    // MARK: - CRUD

    func add(_ word: SavedWord) {
        if words.contains(where: {
            $0.term.lowercased() == word.term.lowercased()
                && $0.pdfFilename == word.pdfFilename
                && $0.pageNumber  == word.pageNumber
                && $0.mode        == word.mode
                && $0.domain      == word.domain
        }) {
            return
        }
        words.insert(word, at: 0)
        save()
        SpotlightIndexer.index(word)
        // Interested services (CEFR estimator) hook new saves through this —
        // save call sites stay decoupled from LLM plumbing.
        NotificationCenter.default.post(name: .savedWordAdded, object: word.id)
    }

    /// Adds many words at once — a Kindle import (v15 S4). One save, and no
    /// `.savedWordAdded` per word: the save-time fill and CEFR estimate
    /// would fire hundreds of model requests at once; the importer starts
    /// one bulk fill instead. Words already saved (same term) are skipped.
    /// Returns the ids added.
    @discardableResult
    func addImported(_ newWords: [SavedWord]) -> [UUID] {
        var terms = Set(words.map { $0.term.lowercased() })
        let added = newWords.filter { terms.insert($0.term.lowercased()).inserted }
        guard !added.isEmpty else { return [] }
        words.insert(contentsOf: added, at: 0)
        save()
        added.forEach(SpotlightIndexer.index)
        return added.map(\.id)
    }

    func update(_ word: SavedWord) {
        guard let index = words.firstIndex(where: { $0.id == word.id }) else { return }
        words[index] = word
        save()
        SpotlightIndexer.index(word)
    }

    /// Merges `others` into `keep` (`WordMerge.merged`) and removes them
    /// (v16 S3). The caller moves their encounters and takes the backup.
    func merge(keep keepID: UUID, others otherIDs: [UUID]) {
        guard let keep = word(withID: keepID) else { return }
        let others = otherIDs.compactMap(word(withID:)).filter { $0.id != keepID }
        guard !others.isEmpty else { return }
        let merged = WordMerge.merged(keep: keep, others: others)
        let removed = Set(others.map(\.id))
        words = words.compactMap { word in
            if word.id == keepID { return merged }
            return removed.contains(word.id) ? nil : word
        }
        save()
        SpotlightIndexer.index(merged)
        removed.forEach(SpotlightIndexer.removeWord)
    }

    func delete(_ word: SavedWord) {
        words.removeAll { $0.id == word.id }
        save()
        SpotlightIndexer.removeWord(id: word.id)
    }

    func delete(at offsets: IndexSet) {
        let removed = offsets.map { words[$0] }
        words.remove(atOffsets: offsets)
        save()
        removed.forEach { SpotlightIndexer.removeWord(id: $0.id) }
    }

    func deleteAll() {
        let removed = words
        words.removeAll()
        save()
        removed.forEach { SpotlightIndexer.removeWord(id: $0.id) }
    }

    /// The saved words without the saved sentences (v19 S2) — what the
    /// level estimate, coverage, underlining, encounters and duplicates
    /// look at.
    var vocabulary: [SavedWord] { words.filter { !$0.isSentence } }

    /// The saved sentences (v19 S2).
    var sentences: [SavedWord] { words.filter(\.isSentence) }

    /// An already-saved word that is the same dictionary word as `term`, even
    /// in a different inflection ("ran" finding a saved "run"). Exact matches
    /// win; lemma matching only runs when nothing matches outright, so this
    /// can add hits but never change an exact one.
    ///
    /// Scoped to the word's own study language so an English "die" isn't
    /// conflated with the German article.
    func lemmaMatchedWord(for term: String, language: Language? = nil) -> SavedWord? {
        let needle = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return nil }

        if let exact = vocabulary.first(where: { $0.term.lowercased() == needle }) {
            return exact
        }

        let studyLanguage = language ?? Language.storedTarget
        let key = LemmaMatcher.matchKey(for: term, language: studyLanguage)
        // A term with no lemma of its own can't match anything but exactly.
        guard key != needle else { return nil }

        return vocabulary.first { word in
            guard word.language == nil || word.language == studyLanguage.rawValue else { return false }
            return LemmaMatcher.matchKey(for: word.term, language: studyLanguage) == key
        }
    }

    /// Trimmed, non-empty terms scoped to one study language — the input to
    /// both readers' saved-word underlining. Without the scope a
    /// multi-language library underlines its German words in an English book,
    /// which is the same mistake `lemmaKeySets(for:)` already avoids for
    /// coverage. Words with no recorded language are pre-v1.24 rows that the
    /// loader backfills, and are kept rather than silently dropped.
    func terms(for language: Language) -> [String] {
        vocabulary.compactMap { word in
            guard word.language == nil || word.language == language.rawValue else { return nil }
            let trimmed = word.term.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    /// Fingerprint of the vocabulary in one study language, stable across
    /// launches — `hashValue` is seeded per process, so it can't tell a
    /// persisted snapshot (`BookCoverage`) whether the words it was computed
    /// from are still the words on disk. FNV-1a over the sorted terms.
    func vocabularyFingerprint(for language: Language) -> String {
        let terms = vocabulary
            .filter { $0.language == nil || $0.language == language.rawValue }
            .map { $0.term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .sorted()

        var hash: UInt64 = 0xcbf29ce484222325
        for byte in terms.joined(separator: "\u{0}").utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return "\(terms.count)-\(String(hash, radix: 16))"
    }

    /// Memoized result of `lemmaKeys(for:)`. One tagger pass per saved word is
    /// far too much to repeat on every highlight refresh (which runs on each
    /// scroll and view update), and the vocabulary changes rarely — the
    /// fingerprint is cheap enough to check every time.
    @ObservationIgnored private var lemmaKeyCache: (fingerprint: Int, language: String, keys: Set<String>)?

    /// Lemma match keys of every saved word in one study language, mastery
    /// ignored — highlighting underlines what you saved whether or not you
    /// have it down yet. `lemmaKeySets(for:)` is the same pass split by
    /// mastery, which is what coverage needs and highlighting doesn't.
    func lemmaKeys(for language: Language) -> Set<String> {
        let terms = vocabulary.compactMap { word -> String? in
            guard word.language == nil || word.language == language.rawValue else { return nil }
            return word.term
        }

        var hasher = Hasher()
        for term in terms { hasher.combine(term) }
        let fingerprint = hasher.finalize()

        if let cached = lemmaKeyCache,
           cached.fingerprint == fingerprint,
           cached.language == language.rawValue {
            return cached.keys
        }

        var keys: Set<String> = []
        for term in terms {
            // Both the lemma and the literal form. A term is lemmatized with
            // no sentence around it, which the tagger sometimes gets wrong
            // (German "Haus" reduces to "Hau"), while the same word inside a
            // page reduces correctly — keeping the literal form as a key lets
            // the two meet. Additive: it can only widen what matches.
            let literal = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !literal.isEmpty { keys.insert(literal) }
            let key = LemmaMatcher.matchKey(for: term, language: language)
            if !key.isEmpty { keys.insert(key) }
        }
        lemmaKeyCache = (fingerprint, language.rawValue, keys)
        return keys
    }

    /// Lemma match keys of the reader's vocabulary, split by whether the word
    /// is mastered or still being learned — the input to a document's coverage
    /// profile (`LexicalProfileBuilder`). Scoped to one study language so a
    /// multi-language library doesn't inflate an English book's coverage with
    /// German words.
    func lemmaKeySets(for language: Language) -> (mastered: Set<String>, learning: Set<String>) {
        var mastered: Set<String> = []
        var learning: Set<String> = []
        for word in vocabulary {
            guard word.language == nil || word.language == language.rawValue else { continue }
            let key = LemmaMatcher.matchKey(for: word.term, language: language)
            guard !key.isEmpty else { continue }
            if word.masteryLevel == .mastered {
                mastered.insert(key)
            } else {
                learning.insert(key)
            }
        }
        // A word can't be both; mastered wins.
        learning.subtract(mastered)
        return (mastered, learning)
    }

    func isSaved(term: String, pdfFilename: String?, pageNumber: Int?) -> Bool {
        words.contains {
            $0.term.lowercased() == term.lowercased()
                && $0.pdfFilename == pdfFilename
                && $0.pageNumber == pageNumber
        }
    }

    func remove(term: String, pdfFilename: String?, pageNumber: Int?) {
        let removed = words.filter {
            $0.term.lowercased() == term.lowercased()
                && $0.pdfFilename == pdfFilename
                && $0.pageNumber == pageNumber
        }
        words.removeAll {
            $0.term.lowercased() == term.lowercased()
                && $0.pdfFilename == pdfFilename
                && $0.pageNumber == pageNumber
        }
        save()
        removed.forEach { SpotlightIndexer.removeWord(id: $0.id) }
    }

    func setMastery(_ level: MasteryLevel, for word: SavedWord) {
        guard let index = words.firstIndex(where: { $0.id == word.id }) else { return }
        words[index].masteryLevel = level
        switch level {
        case .new:
            words[index].nextReviewAt = words[index].savedAt
        case .learning:
            words[index].nextReviewAt = words[index].nextReviewAt ?? Date()
        case .mastered:
            words[index].nextReviewAt = nil
        }
        save()
    }

    func word(withID id: UUID) -> SavedWord? {
        words.first(where: { $0.id == id })
    }

    // MARK: - Tags / Decks

    /// All distinct tags across saved words, sorted case-insensitively.
    var allTags: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for word in words {
            for tag in word.tags {
                let key = tag.lowercased()
                if seen.insert(key).inserted {
                    ordered.append(tag)
                }
            }
        }
        return ordered.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func words(withTag tag: String) -> [SavedWord] {
        words.filter { $0.hasTag(tag) }
    }

    func tagCount(_ tag: String) -> Int {
        words.reduce(0) { $0 + ($1.hasTag(tag) ? 1 : 0) }
    }

    /// User-initiated CEFR assignment — always wins over auto estimates.
    func setCEFRLevel(_ level: CEFRLevel?, for word: SavedWord) {
        guard let index = words.firstIndex(where: { $0.id == word.id }) else { return }
        words[index].cefrLevel = level?.rawValue
        words[index].cefrIsAuto = false
        words[index].fieldSources[FillField.level.rawValue] = nil
        save()
    }

    /// Estimator-initiated CEFR assignment — only ever fills an unrated word,
    /// so a user value can never be silently overwritten.
    func setAutoCEFRLevel(_ level: CEFRLevel, forWordID id: UUID) {
        guard let index = words.firstIndex(where: { $0.id == id }) else { return }
        guard words[index].cefrLevel == nil else { return }
        words[index].cefrLevel = level.rawValue
        words[index].cefrIsAuto = true
        save()
    }

    // MARK: - Filled fields (v15 S1)

    /// Writes a filled-in value — only into a field that's still empty, so a
    /// meaning you saved or typed, or one filled meanwhile, is never
    /// replaced. Returns whether it wrote.
    @discardableResult
    func fill(_ field: FillField, with value: String, source: FillSource, forWordID id: UUID) -> Bool {
        guard let index = words.firstIndex(where: { $0.id == id }),
              field.isMissing(in: words[index]) else { return false }
        switch field {
        case .level:
            guard let level = CEFRLevel(rawValue: value) else { return false }
            words[index].cefrLevel = level.rawValue
            words[index].cefrIsAuto = true
        default:
            guard let module = field.module else { return false }
            words[index].llmOutputs[module.rawValue] = value
        }
        words[index].fieldSources[field.rawValue] = source.stored
        save()
        return true
    }

    /// Rewrites — or with nil empties — a value a fill wrote. A field you
    /// saved or typed has no source and is left alone.
    func replaceFilled(_ field: FillField, with value: String?, forWordID id: UUID) {
        guard let index = words.firstIndex(where: { $0.id == id }),
              words[index].fieldSources[field.rawValue] != nil else { return }
        guard let value else { clear(field, forWordID: id); return }
        switch field {
        case .level:
            guard let level = CEFRLevel(rawValue: value) else { return }
            words[index].cefrLevel = level.rawValue
        default:
            guard let module = field.module else { return }
            words[index].llmOutputs[module.rawValue] = value
        }
        save()
    }

    /// Empties a field and forgets its source — "Remove" on the word page,
    /// and the first half of "Fill again".
    func clear(_ field: FillField, forWordID id: UUID) {
        guard let index = words.firstIndex(where: { $0.id == id }) else { return }
        switch field {
        case .level:
            words[index].cefrLevel = nil
            words[index].cefrIsAuto = false
        default:
            guard let module = field.module else { return }
            words[index].llmOutputs[module.rawValue] = nil
        }
        words[index].fieldSources[field.rawValue] = nil
        save()
    }

    func addTag(_ rawTag: String, to wordID: UUID) {
        let tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty, let index = words.firstIndex(where: { $0.id == wordID }) else { return }
        guard !words[index].hasTag(tag) else { return }
        words[index].tags.append(tag)
        save()
        SpotlightIndexer.index(words[index])   // tags feed the keywords
    }

    func removeTag(_ tag: String, from wordID: UUID) {
        guard let index = words.firstIndex(where: { $0.id == wordID }) else { return }
        let needle = tag.lowercased()
        words[index].tags.removeAll { $0.lowercased() == needle }
        save()
        SpotlightIndexer.index(words[index])
    }

    // MARK: - Bulk operations (one save per call)

    func addTag(_ rawTag: String, toWordsWithIDs ids: Set<UUID>) {
        let tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return }
        var changed: [SavedWord] = []
        for index in words.indices
        where ids.contains(words[index].id) && !words[index].hasTag(tag) {
            words[index].tags.append(tag)
            changed.append(words[index])
        }
        guard !changed.isEmpty else { return }
        save()
        changed.forEach { SpotlightIndexer.index($0) }
    }

    func removeTag(_ tag: String, fromWordsWithIDs ids: Set<UUID>) {
        let needle = tag.lowercased()
        var changed: [SavedWord] = []
        for index in words.indices
        where ids.contains(words[index].id) && words[index].hasTag(tag) {
            words[index].tags.removeAll { $0.lowercased() == needle }
            changed.append(words[index])
        }
        guard !changed.isEmpty else { return }
        save()
        changed.forEach { SpotlightIndexer.index($0) }
    }

    /// Manual bulk CEFR assignment — like the single-word version, always
    /// wins over an auto estimate (`cefrIsAuto` clears on every affected word).
    func setCEFR(_ level: CEFRLevel?, forWordsWithIDs ids: Set<UUID>) {
        var changed = false
        for index in words.indices where ids.contains(words[index].id) {
            words[index].cefrLevel = level?.rawValue
            words[index].cefrIsAuto = false
            words[index].fieldSources[FillField.level.rawValue] = nil
            changed = true
        }
        guard changed else { return }
        save()
    }

    func setMastery(_ level: MasteryLevel, forWordsWithIDs ids: Set<UUID>) {
        var changed = false
        for index in words.indices where ids.contains(words[index].id) {
            words[index].masteryLevel = level
            changed = true
        }
        guard changed else { return }
        save()
    }

    func setLanguage(_ language: Language, forWordsWithIDs ids: Set<UUID>) {
        var changed = false
        for index in words.indices where ids.contains(words[index].id) {
            words[index].language = language.rawValue
            changed = true
        }
        guard changed else { return }
        save()
    }

    func delete(ids: Set<UUID>) {
        let removed = words.filter { ids.contains($0.id) }
        guard !removed.isEmpty else { return }
        words.removeAll { ids.contains($0.id) }
        save()
        removed.forEach { SpotlightIndexer.removeWord(id: $0.id) }
    }


    @discardableResult
    func applyReview(_ rating: ReviewRating, to word: SavedWord, reviewedAt: Date = Date()) -> SavedWord? {
        guard let index = words.firstIndex(where: { $0.id == word.id }) else { return nil }

        // Schedule from the stored word, not the caller's copy, which may be
        // stale — FSRS needs the prior memory state and review date.
        let wasStruggling = words[index].isStruggling
        let updated = Self.reviewed(words[index], rating: rating, at: reviewedAt)
        words[index] = updated
        save()
        if updated.isStruggling && !wasStruggling {
            // A memory hook is filled for it (WordEnricher, v15 S3).
            NotificationCenter.default.post(name: .savedWordStruggling, object: updated.id)
        }
        return updated
    }

    // MARK: - Persistence

    /// Schedules a debounced off-main write of the whole vocabulary. Rapid
    /// mutations (review sessions, bulk edits) coalesce into one write; the
    /// pending value is flushed synchronously at termination via
    /// `PersistenceCoordinator.flushAll()`. `saveError` is updated through the
    /// writer's `onResult` callback.
    private func save() {
        writer.schedule { [words] in try JSONEncoder().encode(words) }
    }

    private static func load(from url: URL) -> [SavedWord] {
        RELLJSONStore.load([SavedWord].self, from: url, storeName: "SavedWordsStore", defaultValue: [])
    }
}
