//
//  WordNotebookTests.swift
//  Reader for Language LearnerTests
//
//  v16 Sprint 2 — the word notebook's books and sources, and the fill that
//  goes through the dictionary for every word first and picks up after a
//  quit.
//

import SwiftUI
import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class WordNotebookTests: XCTestCase {

    // MARK: Books and sources

    func testBooksGatherTheirNamesByTitle() async {
        var words: [SavedWord] = []
        for _ in 0..<3 { words.append(SavedWord(term: "k", pdfFilename: "Why We Sleep", tags: [KindleVocabulary.deckName])) }
        words.append(SavedWord(term: "p", pdfFilename: "Matthew Walker PhD - Why We Sleep_ Unlocking the Power of Sleep and Dreams-Scribner (2017)"))
        words.append(SavedWord(term: "e", pdfFilename: "Why We Sleep_ Unlocking the Power of Sleep and Dreams -- Walker, Matthew -- 2215bb -- Anna’s Archive"))
        for _ in 0..<2 { words.append(SavedWord(term: "h", pdfFilename: "The Hunger Games - Suzanne Collins")) }
        words.append(SavedWord(term: "none"))

        let books = WordNotebook.books(from: words)
        XCTAssertEqual(books.map(\.title), ["Why We Sleep", "The Hunger Games - Suzanne Collins"])
        XCTAssertEqual(books.map(\.count), [5, 2], "three names, one book")
        XCTAssertEqual(WordNotebook.words(for: .book(books[0]), from: words).count, 5)
        XCTAssertEqual(WordNotebook.words(for: .noBook, from: words).map(\.term), ["none"])
        XCTAssertEqual(WordNotebook.words(for: .deck("kindle"), from: words).count, 3)
    }

    func testStateSources() async {
        let now = Date()
        var waiting = SavedWord(term: "waiting"); waiting.reviewCount = 2; waiting.nextReviewAt = now.addingTimeInterval(-60)
        var later = SavedWord(term: "later"); later.reviewCount = 2; later.nextReviewAt = now.addingTimeInterval(86_400)
        var forgot = SavedWord(term: "forgot"); forgot.reviewCount = 4; forgot.incorrectCount = 3
        forgot.nextReviewAt = now.addingTimeInterval(86_400)
        forgot.llmOutputs = [ModuleType.meaningTR.rawValue: "unutulan"]
        let fresh = SavedWord(term: "fresh")
        let words = [waiting, later, forgot, fresh]
        func terms(_ source: WordNotebook.Source) -> Set<String> {
            Set(WordNotebook.words(for: source, from: words, at: now).map(\.term))
        }
        XCTAssertEqual(terms(.waiting), ["waiting"])
        XCTAssertEqual(terms(.new), ["fresh"])
        XCTAssertEqual(terms(.struggling), ["forgot"])
        XCTAssertEqual(terms(.missingMeaning), ["waiting", "later", "fresh"])
    }

    // MARK: Two-pass, resumable fill (decision 5)

    func testTheDictionaryGoesThroughEveryWordBeforeAnyModel() async throws {
        let store = makeStore()
        for term in ["a", "b", "c", "d"] { store.add(SavedWord(term: term, language: Language.english.rawValue)) }
        let enricher = isolated(WordEnricher(store: store, cefrEstimator: nil, observesSaves: false))
        var log: [String] = []
        enricher.backendsOverride = { _ in
            FillBackends(
                dictionary: { log.append("dict-\($0)"); return nil },
                onDevice: { log.append("model-\($0.term)"); return "A definition long enough to keep here." },
                provider: nil, level: nil
            )
        }
        enricher.start(fields: [.definition], allowProvider: false)
        _ = try await finished(enricher)
        let firstModel = try XCTUnwrap(log.firstIndex { $0.hasPrefix("model") })
        XCTAssertEqual(Set(log[..<firstModel]), ["dict-a", "dict-b", "dict-c", "dict-d"])
        XCTAssertEqual(enricher.missingCount(.definition), 0)
        XCTAssertNil(enricher.pendingDefaults.stringArray(forKey: StorageKey.fillPendingWordIDs), "a finished run leaves nothing pending")
    }

    func testARunCutShortGoesOnAtTheNextLaunchLocallyOnly() async throws {
        let store = makeStore()
        let words = ["a", "b"].map { SavedWord(term: $0, language: Language.english.rawValue) }
        words.forEach(store.add)
        let enricher = isolated(WordEnricher(store: store, cefrEstimator: nil, observesSaves: false))
        // What a quit leaves behind.
        enricher.pendingDefaults.set(words.map(\.id.uuidString), forKey: StorageKey.fillPendingWordIDs)
        enricher.pendingDefaults.set([FillField.definition.rawValue], forKey: StorageKey.fillPendingFields)
        var uses: [WordEnricher.ProviderUse] = []
        enricher.backendsOverride = { use in
            uses.append(use)
            return FillBackends(dictionary: { _ in nil }, onDevice: { _ in "A definition long enough to keep here." },
                                provider: nil, level: nil)
        }

        enricher.resumePendingFill()
        _ = try await finished(enricher)
        XCTAssertEqual(enricher.missingCount(.definition), 0)
        XCTAssertEqual(uses, [.never], "nobody pressed a button: no cloud")
        XCTAssertNil(enricher.pendingDefaults.stringArray(forKey: StorageKey.fillPendingWordIDs))
    }

    func testStoppingForgetsTheRun() async throws {
        let store = makeStore()
        store.add(SavedWord(term: "a", language: Language.english.rawValue))
        let enricher = isolated(WordEnricher(store: store, cefrEstimator: nil, observesSaves: false))
        enricher.backendsOverride = { _ in
            FillBackends(dictionary: { _ in nil }, onDevice: { _ in enricher.stop(); return nil }, provider: nil, level: nil)
        }
        enricher.start(fields: [.definition], allowProvider: false)
        _ = try await finished(enricher)
        XCTAssertNil(enricher.pendingDefaults.stringArray(forKey: StorageKey.fillPendingWordIDs), "Stop is a choice")
    }

    // MARK: Layout

    func testTheNotebookFitsItsSmallestWindow() async throws {
        let store = makeStore()
        for index in 0..<30 { store.add(SavedWord(term: "word\(index)", pdfFilename: "Why We Sleep", tags: ["Okul"])) }
        let notebook = WordNotebookView(store: store)
            .environment(WordEncounterStore(fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).appendingPathComponent("e.json")))
            .environment(AnkiModulePreferences())
        let height = try await LayoutGuard.settledHeight(of: notebook, width: 820, height: 560)
        XCTAssertLessThanOrEqual(height, 560 + 1, "the notebook forced the window to \(height) pt")
    }

    // MARK: Helpers

    private func isolated(_ enricher: WordEnricher) -> WordEnricher {
        enricher.pendingDefaults = UserDefaults(suiteName: "WordNotebookTests-\(UUID().uuidString)")!
        return enricher
    }

    private func makeStore() -> SavedWordsStore {
        SavedWordsStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("w.json"))
    }

    private func finished(_ enricher: WordEnricher) async throws -> WordEnricher.Run {
        for _ in 0..<300 where enricher.run?.isFinished != true {
            try await Task.sleep(for: .milliseconds(10))
        }
        return try XCTUnwrap(enricher.run?.isFinished == true ? enricher.run : nil, "the run didn't finish")
    }
}
