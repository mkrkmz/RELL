//
//  InspectorOutputCacheTests.swift
//  Reader for Language LearnerTests
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class InspectorOutputCacheTests: XCTestCase {
    private static var retainedViewModels: [InspectorViewModel] = []

    private func makeTempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("llm_cache_test_\(UUID().uuidString).json")
    }

    private func makeViewModel(fileURL: URL) -> InspectorViewModel {
        let viewModel = InspectorViewModel(cacheFileURL: fileURL)
        Self.retainedViewModels.append(viewModel)
        return viewModel
    }

    private func makeKey(term: String = "orbit") -> OutputCacheKey {
        OutputCacheKey(
            term: term, mode: "Word", detail: "Short", domain: "General",
            provider: "LM Studio", model: "test-model", native: "Turkish"
        )
    }

    func testSnapshotPersistsAcrossInstances() {
        let fileURL = makeTempFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let first = makeViewModel(fileURL: fileURL)
        first.outputs[.definitionEN] = "a circular path"
        first.snapshotToCache(key: makeKey())

        let second = makeViewModel(fileURL: fileURL)
        XCTAssertTrue(second.loadFromCache(key: makeKey()))
        XCTAssertEqual(second.outputs[.definitionEN], "a circular path")
    }

    func testClearCacheRemovesDiskSnapshot() {
        let fileURL = makeTempFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let first = makeViewModel(fileURL: fileURL)
        first.outputs[.definitionEN] = "a circular path"
        first.snapshotToCache(key: makeKey())
        first.clearCache()

        let second = makeViewModel(fileURL: fileURL)
        XCTAssertFalse(second.loadFromCache(key: makeKey()))
    }

    func testMissingFileStartsEmpty() {
        let viewModel = makeViewModel(fileURL: makeTempFileURL())
        XCTAssertFalse(viewModel.loadFromCache(key: makeKey()))
    }

    func testDifferentNativeLanguageMisses() {
        let fileURL = makeTempFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let viewModel = makeViewModel(fileURL: fileURL)
        viewModel.outputs[.meaningTR] = "yörünge"
        viewModel.snapshotToCache(key: makeKey())
        viewModel.resetAll()

        let germanKey = OutputCacheKey(
            term: "orbit", mode: "Word", detail: "Short", domain: "General",
            provider: "LM Studio", model: "test-model", native: "German"
        )
        XCTAssertFalse(viewModel.loadFromCache(key: germanKey))
    }
}

@MainActor
final class ParsedResultCacheTests: XCTestCase {

    func testCollocationEntriesAreMemoizedWithStableIdentity() {
        let content = """
        1. **take orbit:** yörüngeye girmek
           - *Örnek Cümle:* "The satellite took orbit."
           - *Türkçe Çeviri:* "Uydu yörüngeye girdi."
        """

        let first = ParsedResultCache.collocationEntries(for: content)
        let second = ParsedResultCache.collocationEntries(for: content)

        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(
            first.map(\.id), second.map(\.id),
            "Memoized parse should return identical entries (stable IDs) for the same content"
        )
    }

    func testUsageNoteRowsParseLabelsAndValues() {
        let content = """
        FREQ: common — everyday word
        REG: neutral — fits most contexts
        """
        let rows = ParsedResultCache.usageNoteRows(for: content)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.first?.label, "FREQ")
        XCTAssertEqual(rows.first?.value, "common — everyday word")
    }
}
