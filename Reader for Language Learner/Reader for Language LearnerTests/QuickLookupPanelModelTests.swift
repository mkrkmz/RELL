//
//  QuickLookupPanelModelTests.swift
//  Reader for Language LearnerTests
//
//  Only exercises the cache-first path (a SavedWord already carries the
//  definition), which resolves synchronously — no LLM/network call, so
//  no flakiness. The async fetch-and-fail path already goes untested
//  elsewhere in this suite (QuickLookupServiceTests) for the same reason.
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class QuickLookupPanelModelTests: XCTestCase {
    // CI-only gotcha: the macos-15 runner's Swift toolchain SIGABRTs
    // (libmalloc double-free) when XCTest's post-scope memory checker
    // deallocates a @MainActor @Observable object created in a test body.
    // Every store/service/model instance must outlive the test.
    private static var retainedStores: [SavedWordsStore] = []
    private static var retainedServices: [QuickLookupService] = []
    private static var retainedModels: [QuickLookupPanelModel] = []

    func testTrimmedQueryStripsWhitespace() {
        let model = makeModel()
        model.query = "  serendipity  "
        XCTAssertEqual(model.trimmedQuery, "serendipity")
    }

    func testLookupWithEmptyQueryStaysIdle() {
        let model = makeModel()
        model.query = "   "
        model.lookup(service: makeService(), savedWords: makeStore())
        XCTAssertEqual(model.phase, .idle)
    }

    func testLookupResolvesInstantlyFromSavedWordCache() {
        let store = makeStore()
        store.add(SavedWord(
            term: "ephemeral", sentence: "", pdfFilename: nil, pageNumber: nil,
            mode: "word", domain: "general",
            llmOutputs: [ModuleType.definitionEN.rawValue: "Lasting for a very short time."]
        ))

        let model = makeModel()
        model.query = "ephemeral"
        model.lookup(service: makeService(), savedWords: store)

        XCTAssertEqual(model.phase, .loaded("Lasting for a very short time."))
        XCTAssertTrue(model.isCurrentTermSaved(in: store))
    }

    func testIsCurrentTermSavedIsCaseInsensitiveAndFalseBeforeLookup() {
        let store = makeStore()
        store.add(SavedWord(
            term: "Ephemeral", sentence: "", pdfFilename: nil, pageNumber: nil,
            mode: "word", domain: "general", llmOutputs: [:]
        ))
        let model = makeModel()

        XCTAssertFalse(model.isCurrentTermSaved(in: store))

        model.query = "ephemeral"
        model.lookup(service: makeService(), savedWords: store)
        XCTAssertTrue(model.isCurrentTermSaved(in: store))
    }

    func testSaveWordAddsEntryOnlyWhenLoaded() {
        let cacheStore = makeStore()
        cacheStore.add(SavedWord(
            term: "lucid", sentence: "", pdfFilename: nil, pageNumber: nil,
            mode: "word", domain: "general",
            llmOutputs: [ModuleType.definitionEN.rawValue: "Clear and easy to understand."]
        ))

        let model = makeModel()
        model.query = "lucid"
        model.lookup(service: makeService(), savedWords: cacheStore)

        let destination = makeStore()
        XCTAssertFalse(destination.isSaved(term: "lucid", pdfFilename: nil, pageNumber: nil))
        model.saveWord(to: destination)
        XCTAssertTrue(destination.isSaved(term: "lucid", pdfFilename: nil, pageNumber: nil))
    }

    func testSaveWordIsNoOpWhileIdle() {
        let model = makeModel()
        let store = makeStore()
        model.saveWord(to: store)
        XCTAssertTrue(store.words.isEmpty)
    }

    func testResetReturnsToIdleAndClearsQuery() {
        let store = makeStore()
        store.add(SavedWord(
            term: "lucid", sentence: "", pdfFilename: nil, pageNumber: nil,
            mode: "word", domain: "general",
            llmOutputs: [ModuleType.definitionEN.rawValue: "Clear and easy to understand."]
        ))
        let model = makeModel()
        model.query = "lucid"
        model.lookup(service: makeService(), savedWords: store)

        model.reset()

        XCTAssertEqual(model.query, "")
        XCTAssertEqual(model.phase, .idle)
        XCTAssertFalse(model.isCurrentTermSaved(in: store))
    }

    // MARK: - Helpers

    private func makeModel() -> QuickLookupPanelModel {
        let model = QuickLookupPanelModel()
        Self.retainedModels.append(model)
        return model
    }

    private func makeStore() -> SavedWordsStore {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let store = SavedWordsStore(fileURL: fileURL)
        Self.retainedStores.append(store)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: fileURL)
        }
        return store
    }

    private func makeService() -> QuickLookupService {
        let service = QuickLookupService()
        Self.retainedServices.append(service)
        return service
    }
}
