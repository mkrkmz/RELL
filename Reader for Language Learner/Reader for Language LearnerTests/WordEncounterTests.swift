//
//  WordEncounterTests.swift
//  Reader for Language LearnerTests
//
//  The encounter log (v13 Sprint 1): which saved words a passage contains,
//  the sentence each is shown with, and how the store dedupes, caps and
//  forgets deleted words.
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class WordEncounterTests: XCTestCase {
    private static var retainedStores: [WordEncounterStore] = []

    // MARK: - Scanner

    func testFindsWordAndItsSentence() async {
        let run = EncounterScanner.Entry(id: UUID(), term: "orbit")
        let hits = EncounterScanner.scan(
            text: "The night was clear. A satellite kept its orbit above us. Nobody slept.",
            vocabulary: [run],
            language: .english
        )
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.wordID, run.id)
        XCTAssertEqual(hits.first?.sentence, "A satellite kept its orbit above us.")
    }

    /// Inflections count — the log is only useful if "ran" finds "run".
    func testFindsInflectedForms() async {
        let run = EncounterScanner.Entry(id: UUID(), term: "run")
        let hits = EncounterScanner.scan(
            text: "She ran for the train. Later he ran again.",
            vocabulary: [run],
            language: .english
        )
        XCTAssertEqual(hits.first?.wordID, run.id)
        XCTAssertEqual(hits.first?.sentence, "She ran for the train.")
        XCTAssertEqual(hits.first?.occurrences, 2)
    }

    /// Found live on a PDF page: the running head came first and was shown
    /// as the sentence. A line of real prose wins over a title.
    func testPrefersProseOverAHeading() async {
        let sleep = EncounterScanner.Entry(id: UUID(), term: "sleep")
        let hits = EncounterScanner.scan(
            text: "REM-Sleep Dreaming\nWe spend a third of our lives asleep, and sleep shapes every part of it.",
            vocabulary: [sleep],
            language: .english
        )
        XCTAssertEqual(hits.first?.sentence, "We spend a third of our lives asleep, and sleep shapes every part of it.")
    }

    /// Whole-word only, the same rule the underlining uses.
    func testDoesNotMatchInsideLongerWords() async {
        let hits = EncounterScanner.scan(
            text: "They bore the brunt of it.",
            vocabulary: [.init(id: UUID(), term: "run")],
            language: .english
        )
        XCTAssertTrue(hits.isEmpty)
    }

    func testPhrasesMatchLiterally() async {
        let phrase = EncounterScanner.Entry(id: UUID(), term: "give up")
        let hits = EncounterScanner.scan(
            text: "Never give up on it. That is all.",
            vocabulary: [phrase],
            language: .english
        )
        XCTAssertEqual(hits.first?.sentence, "Never give up on it.")
    }

    /// PDF text breaks lines and hyphenates; the sentence should read as one.
    func testSentenceIsNormalized() async {
        XCTAssertEqual(
            EncounterScanner.normalize("A satel-\nlite kept\n its  orbit."),
            "A satellite kept its orbit."
        )
    }

    /// A page with no punctuation is one huge "sentence"; keep a window
    /// around the match instead.
    func testLongSentenceIsWindowedAroundTheMatch() async {
        let filler = String(repeating: "word ", count: 200)
        let text = filler + "orbit " + filler
        let hits = EncounterScanner.scan(
            text: text,
            vocabulary: [.init(id: UUID(), term: "orbit")],
            language: .english
        )
        let sentence = try? XCTUnwrap(hits.first?.sentence)
        XCTAssertNotNil(sentence)
        XCTAssertLessThanOrEqual(sentence?.count ?? .max, EncounterScanner.maxSentenceLength)
        XCTAssertTrue(sentence?.contains("orbit") == true)
    }

    // MARK: - Store

    func testRecordReadLogsSavedWordsAndSkipsTheSavedSentence() async throws {
        let store = try makeStore()
        let word = SavedWord(term: "orbit", sentence: "A satellite kept its orbit above us.", language: "English")
        let text = "A satellite kept its orbit above us. The moon's orbit is slow."

        store.recordRead(
            text: { text }, documentPath: "/b.pdf", documentTitle: "B",
            location: 3, isEPUB: false, words: [word], language: .english
        )
        await store.waitForPendingScan()

        // The first sentence is where the word was saved from; the scanner
        // reports the first occurrence only, so nothing new is logged here.
        XCTAssertTrue(store.encounters(for: word.id).isEmpty)

        store.recordRead(
            text: { "The moon's orbit is slow." }, documentPath: "/b.pdf", documentTitle: "B",
            location: 4, isEPUB: false, words: [word], language: .english
        )
        await store.waitForPendingScan()
        let logged = store.encounters(for: word.id)
        XCTAssertEqual(logged.count, 1)
        XCTAssertEqual(logged.first?.sentence, "The moon's orbit is slow.")
        XCTAssertEqual(logged.first?.location, 4)
        XCTAssertEqual(logged.first?.documentTitle, "B")
    }

    /// Words saved in another study language aren't looked for.
    func testRecordReadIgnoresOtherLanguages() async throws {
        let store = try makeStore()
        let german = SavedWord(term: "orbit", language: "German")
        store.recordRead(
            text: { "Its orbit is slow." }, documentPath: "/b.pdf", documentTitle: "B",
            location: 0, isEPUB: false, words: [german], language: .english
        )
        await store.waitForPendingScan()
        XCTAssertTrue(store.encounters.isEmpty)
    }

    func testSamePlaceSameDayIsLoggedOnce() async throws {
        let store = try makeStore()
        let id = UUID()
        let now = Date()
        store.append([encounter(id, location: 1, date: now)])
        store.append([encounter(id, location: 1, date: now.addingTimeInterval(60))])
        store.append([encounter(id, location: 2, date: now)])
        XCTAssertEqual(store.encounters(for: id).count, 2)
    }

    func testCapsEachWordToItsNewest() async throws {
        let store = try makeStore()
        let id = UUID()
        let start = Date(timeIntervalSince1970: 1_000_000)
        let many = (0..<(WordEncounterStore.maxPerWord + 5)).map {
            encounter(id, location: $0, date: start.addingTimeInterval(Double($0) * 86_400))
        }
        store.append(many)
        let kept = store.encounters(for: id)
        XCTAssertEqual(kept.count, WordEncounterStore.maxPerWord)
        XCTAssertEqual(kept.last?.location, 5, "the five oldest are dropped")
    }

    func testDeletedWordsAreForgotten() async throws {
        let store = try makeStore()
        let kept = UUID(), deleted = UUID()
        store.append([encounter(kept, location: 0), encounter(deleted, location: 0)])
        store.append([], keepingWords: [kept])
        XCTAssertEqual(store.encounters.map(\.wordID), [kept])
    }

    func testPersistsAndReloads() async throws {
        let url = tempURL()
        let store = WordEncounterStore(fileURL: url)
        Self.retainedStores.append(store)
        let id = UUID()
        store.append([encounter(id, location: 7)])
        store.flush()

        let reloaded = WordEncounterStore(fileURL: url)
        Self.retainedStores.append(reloaded)
        XCTAssertEqual(reloaded.encounters(for: id).first?.location, 7)
    }

    /// The v13 persistence rule: an unreadable log is set aside, not
    /// overwritten by the next write.
    func testCorruptFileIsQuarantinedNotOverwritten() async throws {
        let url = tempURL()
        try Data("{not json".utf8).write(to: url)
        let store = WordEncounterStore(fileURL: url)
        Self.retainedStores.append(store)
        XCTAssertTrue(store.encounters.isEmpty)

        let folder = url.deletingLastPathComponent()
        let quarantined = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasPrefix(url.deletingPathExtension().lastPathComponent + ".corrupt-") }
        XCTAssertEqual(quarantined.count, 1)
        _ = PersistenceRecovery.takePending()
    }

    func testClozeSentencesSkipTheSavedOneAndDuplicates() async throws {
        let store = try makeStore()
        let id = UUID()
        store.append([
            encounter(id, location: 0, sentence: "Saved one."),
            encounter(id, location: 1, sentence: "Another one."),
            encounter(id, location: 2, sentence: "another one."),
        ])
        XCTAssertEqual(store.sentences(for: id, excluding: "Saved one."), ["Another one."])
    }

    func testEncounterFileIsBackedUp() async {
        XCTAssertTrue(PersistenceBackup.dataFiles.contains(WordEncounterStore.fileName))
    }

    // MARK: - Helpers

    private func encounter(
        _ wordID: UUID, location: Int, date: Date = Date(), sentence: String = "It was there."
    ) -> WordEncounter {
        WordEncounter(
            wordID: wordID, documentPath: "/b.pdf", documentTitle: "B",
            location: location, isEPUB: false, sentence: sentence, occurrences: 1, date: date
        )
    }

    private func tempURL() -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder.appendingPathComponent(WordEncounterStore.fileName)
    }

    private func makeStore() throws -> WordEncounterStore {
        let store = WordEncounterStore(fileURL: tempURL())
        Self.retainedStores.append(store)
        return store
    }
}
