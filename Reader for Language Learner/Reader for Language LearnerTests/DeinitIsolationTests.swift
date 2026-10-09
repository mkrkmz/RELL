//
//  DeinitIsolationTests.swift
//  Reader for Language LearnerTests
//
//  v16 Sprint 0 — on macOS 15 a main-actor deinit that runs outside a task
//  and releases another main-actor object crashed (CI crash reports: a
//  store releasing its writer; a fill service releasing its store). These
//  tests are synchronous on purpose: an async test body runs in a task,
//  where the bug doesn't show. They matter on CI's macOS 15 runner.
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class DeinitIsolationTests: XCTestCase {

    func testAStoreAndItsWriterReleaseOutsideATask() {
        var store: SavedWordsStore? = makeStore()
        store?.add(SavedWord(term: "landlady"))
        store = nil
        XCTAssertNil(store)
    }

    func testServicesHoldingAStoreReleaseOutsideATask() {
        var enricher: WordEnricher? = WordEnricher(store: makeStore(), cefrEstimator: nil, observesSaves: false)
        var session: QuizSession? = QuizSession()
        session?.begin(with: [SavedWord(term: "a")], mode: .flashcard)
        enricher = nil
        session = nil
        XCTAssertNil(enricher)
        XCTAssertNil(session)
    }

    func testAReaderWindowsModelsReleaseOutsideATask() {
        var model: ReaderWindowModel? = ReaderWindowModel()
        var inspector: InspectorViewModel? = InspectorViewModel()
        model = nil
        inspector = nil
        XCTAssertNil(model)
        XCTAssertNil(inspector)
    }

    private func makeStore() -> SavedWordsStore {
        SavedWordsStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("w.json"))
    }
}
