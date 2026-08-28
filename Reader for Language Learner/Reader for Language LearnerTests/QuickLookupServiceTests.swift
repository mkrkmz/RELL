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

    /// Retained for the class lifetime so the service (and its AsyncLimiter
    /// actor) isn't deallocated inside XCTest's post-scope memory checker —
    /// that actor-deinit path crashes the Swift concurrency runtime on the CI
    /// toolchain. The app keeps a single QuickLookupService alive anyway.
    private func makeService() -> QuickLookupService {
        let service = QuickLookupService()
        Self.retained.append(service)
        return service
    }

    private func makeSavedStore() -> SavedWordsStore {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("quicklookup_words_\(UUID().uuidString).json")
        let store = SavedWordsStore(fileURL: fileURL)
        Self.retained.append(store)
        addTeardownBlock { try? FileManager.default.removeItem(at: fileURL) }
        return store
    }

    func testCachedDefinitionUsesSavedWord() {
        let service = makeService()
        let store = makeSavedStore()
        store.add(SavedWord(
            term: "presuppose",
            llmOutputs: [ModuleType.definitionEN.rawValue: "to assume beforehand"]
        ))

        // Case-insensitive match returns the saved definition without any LLM call.
        XCTAssertEqual(service.cachedDefinition(for: "Presuppose", savedWordsStore: store),
                       "to assume beforehand")
    }

    /// "unsaved" used to stand in for a miss here. Since v1.38 the instant
    /// layer also asks macOS's dictionaries, and a real word is no longer a
    /// miss on a machine whose dictionaries cover it — so the miss case needs
    /// a term nothing can answer.
    func testCachedDefinitionMissReturnsNil() {
        let service = makeService()
        let store = makeSavedStore()
        XCTAssertNil(service.cachedDefinition(for: "zzqqxyw", savedWordsStore: store))
    }

    /// The system dictionary answers instantly, before any model call — but
    /// only in the language the reader asked to be answered in, which is what
    /// keeps it from overriding that choice (see `SystemDictionary`).
    func testCachedDefinitionCanComeFromTheSystemDictionary() throws {
        let target = Language.storedTarget
        let expected = SystemDictionary.definition(for: "sleep", in: target)
        try XCTSkipIf(
            expected == nil,
            "No active dictionary answers \"sleep\" in \(target.rawValue) on this machine"
        )

        let service = makeService()
        let store = makeSavedStore()
        XCTAssertEqual(service.cachedDefinition(for: "sleep", savedWordsStore: store), expected)
    }

    /// A saved word still wins: the reader's own material outranks the
    /// system's.
    func testSavedWordOutranksTheSystemDictionary() {
        let service = makeService()
        let store = makeSavedStore()
        store.add(SavedWord(
            term: "sleep",
            llmOutputs: [ModuleType.definitionEN.rawValue: "my own note about sleep"]
        ))

        XCTAssertEqual(
            service.cachedDefinition(for: "sleep", savedWordsStore: store),
            "my own note about sleep"
        )
    }

    func testCachedDefinitionIgnoresPlaceholderDefinition() {
        let service = makeService()
        let store = makeSavedStore()
        // A saved word with no usable outputs resolves to the placeholder,
        // which must not be served as a definition.
        store.add(SavedWord(term: "bareword"))
        XCTAssertNil(service.cachedDefinition(for: "bareword", savedWordsStore: store))
    }

    func testCachedTranslationEmptyForUnknownSentence() {
        let service = makeService()
        XCTAssertNil(service.cachedTranslation(for: "an unseen sentence"))
    }

    func testCachedNativeMeaningMissReturnsNil() {
        let service = makeService()
        XCTAssertNil(service.cachedNativeMeaning(for: "unseen"))
    }
}
