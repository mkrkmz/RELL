//
//  WordEncounterStore.swift
//  Reader for Language Learner
//
//  The encounter log (Roadmap v13 Sprint 1): every page or chapter the reader
//  actually stayed on is scanned for saved words, and each one found is
//  logged with the sentence it appeared in.
//
//  Kept out of `saved_words.json` on purpose — it grows with every reading
//  session, so it lives in its own file, capped per word, written through the
//  same debounced writer and covered by the same backups and quarantine.
//

import Foundation

@MainActor
@Observable
final class WordEncounterStore {

    static let fileName = "word_encounters.json"
    /// Newest encounters kept per word. Enough for a timeline and for cloze
    /// cards to rotate through contexts; old ones age out.
    static let maxPerWord = 50

    private(set) var encounters: [WordEncounter] = []

    @ObservationIgnored private let writer: DebouncedFileWriter
    @ObservationIgnored private var scanTask: Task<Void, Never>?

    init(fileURL customFileURL: URL? = nil) {
        let resolved = DebouncedFileWriter.forAppSupport(
            filename: Self.fileName,
            storeName: "WordEncounterStore",
            customFileURL: customFileURL
        )
        self.writer = resolved.writer
        self.encounters = resolved.canLoad
            ? RELLJSONStore.load([WordEncounter].self, from: resolved.url, storeName: "WordEncounterStore", defaultValue: [])
            : []
    }

    // MARK: - Queries

    /// A word's encounters, newest first.
    func encounters(for wordID: UUID) -> [WordEncounter] {
        encounters.filter { $0.wordID == wordID }.sorted { $0.date > $1.date }
    }

    /// Distinct documents a word was met in.
    func documentCount(for wordID: UUID) -> Int {
        Set(encounters.lazy.filter { $0.wordID == wordID }.map(\.documentPath)).count
    }

    /// Distinct sentences a word was met in — the saved sentence excluded —
    /// for cloze cards that shouldn't repeat the same context.
    func sentences(for wordID: UUID, excluding saved: String) -> [String] {
        let savedKey = EncounterScanner.normalize(saved).lowercased()
        var seen: Set<String> = [savedKey]
        var result: [String] = []
        for encounter in encounters(for: wordID) {
            let key = encounter.sentence.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(encounter.sentence)
        }
        return result
    }

    // MARK: - Recording

    /// Scans a passage the reader stayed on and logs the saved words in it.
    /// Text extraction and the scan run off the main actor (an EPUB chapter
    /// parses its XHTML on a cache miss); a newer call cancels an older one
    /// still running (the reader has moved on).
    func recordRead(
        text: @escaping @Sendable () -> String,
        documentPath: String,
        documentTitle: String,
        location: Int,
        isEPUB: Bool,
        words: [SavedWord],
        language: Language,
        now: Date = Date()
    ) {
        let vocabulary = words.compactMap { word -> EncounterScanner.Entry? in
            guard word.language == nil || word.language == language.rawValue else { return nil }
            return EncounterScanner.Entry(id: word.id, term: word.term)
        }
        // The sentence each word was saved from is where it came from, not
        // somewhere it was met again.
        let savedSentences = Dictionary(uniqueKeysWithValues: words.map {
            ($0.id, EncounterScanner.normalize($0.sentence).lowercased())
        })
        let liveIDs = Set(words.map(\.id))
        guard !vocabulary.isEmpty else { return }

        scanTask?.cancel()
        scanTask = Task { [weak self] in
            let hits = await Task.detached(priority: .utility) {
                EncounterScanner.scan(text: text(), vocabulary: vocabulary, language: language)
            }.value
            guard !Task.isCancelled, let self else { return }
            let fresh = hits
                .filter { savedSentences[$0.wordID] != $0.sentence.lowercased() }
                .map {
                    WordEncounter(
                        wordID: $0.wordID,
                        documentPath: documentPath,
                        documentTitle: documentTitle,
                        location: location,
                        isEPUB: isEPUB,
                        sentence: $0.sentence,
                        occurrences: $0.occurrences,
                        date: now
                    )
                }
            self.append(fresh, keepingWords: liveIDs)
        }
    }

    /// Adds encounters, skipping any already logged for the same word, place
    /// and day, then drops encounters of deleted words and trims each word to
    /// `maxPerWord`. Saves only when something changed.
    func append(_ new: [WordEncounter], keepingWords liveIDs: Set<UUID>? = nil) {
        let calendar = Calendar.current
        var updated = encounters
        var changed = false

        for encounter in new {
            let duplicate = updated.contains {
                $0.wordID == encounter.wordID
                    && $0.documentPath == encounter.documentPath
                    && $0.location == encounter.location
                    && calendar.isDate($0.date, inSameDayAs: encounter.date)
            }
            guard !duplicate else { continue }
            updated.append(encounter)
            changed = true
        }

        if let liveIDs {
            let before = updated.count
            updated.removeAll { !liveIDs.contains($0.wordID) }
            changed = changed || updated.count != before
        }

        let trimmed = Self.capped(updated)
        changed = changed || trimmed.count != updated.count
        guard changed else { return }
        encounters = trimmed
        save()
    }

    /// Newest `maxPerWord` per word; order otherwise preserved.
    static func capped(_ list: [WordEncounter]) -> [WordEncounter] {
        var kept: Set<UUID> = []
        let byWord = Dictionary(grouping: list, by: \.wordID)
        for (_, group) in byWord {
            for encounter in group.sorted(by: { $0.date > $1.date }).prefix(maxPerWord) {
                kept.insert(encounter.id)
            }
        }
        return list.filter { kept.contains($0.id) }
    }

    // MARK: - Persistence

    private func save() {
        writer.schedule { [encounters] in try JSONEncoder().encode(encounters) }
    }

    /// Tests and termination: write any pending change now.
    func flush() { writer.flush() }

    #if DEBUG
    /// Tests only: waits for the scan `recordRead` started.
    func waitForPendingScan() async { await scanTask?.value }
    #endif
}
