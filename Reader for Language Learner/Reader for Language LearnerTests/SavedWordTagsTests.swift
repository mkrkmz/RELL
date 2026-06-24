//
//  SavedWordTagsTests.swift
//  Reader for Language LearnerTests
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class SavedWordTagsTests: XCTestCase {
    private static var retained: [SavedWordsStore] = []

    private func makeStore() -> SavedWordsStore {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tags_words_\(UUID().uuidString).json")
        let store = SavedWordsStore(fileURL: fileURL)
        Self.retained.append(store)
        addTeardownBlock { try? FileManager.default.removeItem(at: fileURL) }
        return store
    }

    // MARK: - Model

    func testHasTagIsCaseInsensitive() {
        let word = SavedWord(term: "orbit", tags: ["Physics"])
        XCTAssertTrue(word.hasTag("physics"))
        XCTAssertTrue(word.hasTag("PHYSICS"))
        XCTAssertFalse(word.hasTag("chemistry"))
    }

    func testCodableRoundTripWithTags() throws {
        let word = SavedWord(term: "orbit", tags: ["physics", "space"])
        let data = try JSONEncoder().encode(word)
        let decoded = try JSONDecoder().decode(SavedWord.self, from: data)
        XCTAssertEqual(decoded.tags, ["physics", "space"])
    }

    func testDecodeLegacyWordWithoutTags() throws {
        let legacy = """
        {"id":"\(UUID().uuidString)","term":"orbit","mode":"Word","domain":"General"}
        """
        let decoded = try JSONDecoder().decode(SavedWord.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.tags, [])
    }

    // MARK: - Store

    func testAllTagsAreDistinctAndSorted() {
        let store = makeStore()
        store.add(SavedWord(term: "a", tags: ["space", "Physics"]))
        store.add(SavedWord(term: "b", tags: ["physics", "biology"]))

        // "physics" appears twice with different casing → one entry.
        XCTAssertEqual(store.allTags.map { $0.lowercased() }, ["biology", "physics", "space"])
    }

    func testAddAndRemoveTag() {
        let store = makeStore()
        let word = SavedWord(term: "orbit")
        store.add(word)

        store.addTag("space", to: word.id)
        store.addTag("space", to: word.id) // duplicate ignored
        XCTAssertEqual(store.word(withID: word.id)?.tags, ["space"])

        store.removeTag("SPACE", from: word.id)
        XCTAssertEqual(store.word(withID: word.id)?.tags, [])
    }

    func testWordsWithTagAndCount() {
        let store = makeStore()
        store.add(SavedWord(term: "a", tags: ["space"]))
        store.add(SavedWord(term: "b", tags: ["space"]))
        store.add(SavedWord(term: "c", tags: ["biology"]))

        XCTAssertEqual(store.words(withTag: "space").count, 2)
        XCTAssertEqual(store.tagCount("space"), 2)
        XCTAssertEqual(store.tagCount("biology"), 1)
    }

    func testReviewQueueScopedToDeck() {
        let store = makeStore()
        store.add(SavedWord(term: "spaceword", tags: ["space"]))
        store.add(SavedWord(term: "bioword", tags: ["biology"]))

        let deck = store.reviewQueue(includeAll: true, tag: "space")
        XCTAssertEqual(deck.map(\.term), ["spaceword"])

        let all = store.reviewQueue(includeAll: true, tag: nil)
        XCTAssertEqual(all.count, 2)
    }

    func testReviewQueueFallsBackWithinDeck() {
        let store = makeStore()
        // A non-due, non-mastered word in the deck should still appear via fallback.
        var word = SavedWord(term: "spaceword", tags: ["space"], masteryLevel: .learning)
        word.nextReviewAt = Date().addingTimeInterval(60 * 60 * 24) // not due
        store.add(word)

        let queue = store.reviewQueue(includeAll: false, tag: "space")
        XCTAssertEqual(queue.map(\.term), ["spaceword"])
    }

    // MARK: - Export

    func testAnkiExportMergesWordTags() {
        let note = AnkiExporter.buildNote(
            selectedText: "orbit",
            mode: .word,
            domain: .general,
            selectedModules: [],
            outputs: [:],
            includeSource: false,
            pdfFilename: nil,
            pageNumber: nil,
            tags: "rell",
            extraTags: ["space", "physics"]
        )
        XCTAssertEqual(note.tags, "rell space physics")
    }

    func testAnkiExportDedupesAndUnderscoresTags() {
        let note = AnkiExporter.buildNote(
            selectedText: "orbit",
            mode: .word,
            domain: .general,
            selectedModules: [],
            outputs: [:],
            includeSource: false,
            pdfFilename: nil,
            pageNumber: nil,
            tags: "rell space",
            extraTags: ["space", "deep space"]
        )
        // "space" deduped against the base tag; "deep space" → "deep_space".
        XCTAssertEqual(note.tags, "rell space deep_space")
    }
}
