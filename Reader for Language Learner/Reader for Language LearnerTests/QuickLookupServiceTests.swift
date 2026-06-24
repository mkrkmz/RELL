//
//  QuickLookupServiceTests.swift
//  Reader for Language LearnerTests
//
//  Covers the cache-first paths that don't require a live LLM server.
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class QuickLookupServiceTests: XCTestCase {
    private static var retained: [Any] = []

    private func makeSavedStore() -> SavedWordsStore {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("quicklookup_words_\(UUID().uuidString).json")
        let store = SavedWordsStore(fileURL: fileURL)
        Self.retained.append(store)
        addTeardownBlock { try? FileManager.default.removeItem(at: fileURL) }
        return store
    }

    func testCachedDefinitionUsesSavedWord() {
        let service = QuickLookupService()
        let store = makeSavedStore()
        store.add(SavedWord(
            term: "presuppose",
            llmOutputs: [ModuleType.definitionEN.rawValue: "to assume beforehand"]
        ))

        // Case-insensitive match returns the saved definition without any LLM call.
        XCTAssertEqual(service.cachedDefinition(for: "Presuppose", savedWordsStore: store),
                       "to assume beforehand")
    }

    func testCachedDefinitionMissReturnsNil() {
        let service = QuickLookupService()
        let store = makeSavedStore()
        XCTAssertNil(service.cachedDefinition(for: "unsaved", savedWordsStore: store))
    }

    func testCachedDefinitionIgnoresPlaceholderDefinition() {
        let service = QuickLookupService()
        let store = makeSavedStore()
        // A saved word with no usable outputs resolves to the placeholder,
        // which must not be served as a definition.
        store.add(SavedWord(term: "bareword"))
        XCTAssertNil(service.cachedDefinition(for: "bareword", savedWordsStore: store))
    }

    func testCachedTranslationEmptyForUnknownSentence() {
        let service = QuickLookupService()
        XCTAssertNil(service.cachedTranslation(for: "an unseen sentence"))
    }
}
