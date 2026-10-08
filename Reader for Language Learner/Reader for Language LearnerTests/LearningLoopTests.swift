//
//  LearningLoopTests.swift
//  Reader for Language LearnerTests
//
//  v15 Sprint 3 — the exercise follows the word's stage, a new word is
//  introduced before it's asked, cloze sentences prefer ones with nothing
//  else unfamiliar in them, and a word you keep forgetting gets a memory
//  hook — from a server on this Mac only.
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class LearningLoopTests: XCTestCase {

    // MARK: By stage

    func testTheExerciseFollowsTheStage() async {
        let defined = [ModuleType.meaningTR.rawValue: "ev sahibesi"]
        var word = SavedWord(term: "landlady", sentence: "He owed his landlady money.", llmOutputs: defined)
        XCTAssertEqual(QuizMode.stageMode(for: word, canSpeak: true), .multipleChoice, "new: recognise it")

        word.reviewCount = 3
        word.masteryLevel = .learning
        XCTAssertEqual(QuizMode.stageMode(for: word, canSpeak: true), .typed, "learning: recall it")

        word.masteryLevel = .mastered
        XCTAssertEqual(QuizMode.stageMode(for: word, canSpeak: true), .listening, "settled: hear it")
        XCTAssertEqual(QuizMode.stageMode(for: word, canSpeak: false), .typed, "no voice for it")

        let bare = SavedWord(term: "zyx")
        XCTAssertEqual(QuizMode.stageMode(for: bare, canSpeak: true), .flashcard, "nothing to ask about")
    }

    func testMixedRunsPickTheExercisePerCard() async {
        let session = QuizSession()
        session.modeResolver = { $0.term == "a" ? .typed : .multipleChoice }
        session.optionsBuilder = { _ in ["a", "b", "c", "d"] }
        session.begin(with: ["a", "b"].map { SavedWord(term: $0) }, mode: .mixed, shuffle: false)
        XCTAssertEqual(session.currentMode, .typed)
        XCTAssertTrue(session.mcOptions.isEmpty)
        session.advance(mode: .mixed)
        XCTAssertEqual(session.currentMode, .multipleChoice)
        XCTAssertEqual(session.mcOptions.count, 4)
    }

    // MARK: Introductions

    func testANewWordIsIntroducedThenAskedAFewCardsLater() async {
        var known = ["b", "c", "d"].map { SavedWord(term: $0) }
        for index in known.indices { known[index].reviewCount = 2 }
        let session = QuizSession()
        session.introducesNewWords = true
        session.begin(with: [SavedWord(term: "new")] + known, mode: .flashcard, shuffle: false)

        XCTAssertTrue(session.isIntroducing)
        session.finishIntroduction(mode: .flashcard)
        XCTAssertEqual(session.queue.map(\.term), ["b", "c", "d", "new"])
        XCTAssertFalse(session.isIntroducing, "a reviewed word isn't introduced")
        for _ in 0..<3 { session.advance(mode: .flashcard) }
        XCTAssertEqual(session.currentWord?.term, "new")
        XCTAssertFalse(session.isIntroducing, "introduced once; now it's asked")
    }

    func testTheSidebarDoesNotIntroduce() async {
        let session = QuizSession()
        session.begin(with: [SavedWord(term: "new")], mode: .flashcard)
        XCTAssertFalse(session.isIntroducing)
    }

    // MARK: i+1 sentences

    func testClozePrefersASentenceWithNothingElseUnfamiliar() async {
        let word = SavedWord(term: "landlady", sentence: "The landlady scolded the lodger.")
        let met = WordEncounter(wordID: word.id, documentPath: "/b.epub", documentTitle: "B", location: 0, isEPUB: true,
                                sentence: "His landlady was kind.", occurrences: 1, date: Date())
        for reviews in 0..<3 {
            var asked = word
            asked.reviewCount = reviews
            let choice = ClozeContext.choice(for: asked, encounters: [met], unfamiliar: ["lodger", "scold"])
            XCTAssertEqual(choice?.source?.sentence, "His landlady was kind.", "review \(reviews)")
        }
        XCTAssertEqual(ClozeContext.unfamiliarCount(in: "The ___ scolded the lodger.", unfamiliar: ["lodger", "scold"]), 1,
                       "whole words only: scolded isn't scold")
    }

    // MARK: Words you keep forgetting

    func testTheSecondAgainMarksTheWordOnce() async throws {
        let store = makeStore()
        let word = SavedWord(term: "jeering")
        store.add(word)
        var posts = 0
        let observer = NotificationCenter.default.addObserver(forName: .savedWordStruggling, object: nil, queue: nil) { note in
            if note.object as? UUID == word.id { posts += 1 }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        store.applyReview(.again, to: word)
        XCTAssertFalse(try XCTUnwrap(store.word(withID: word.id)).isStruggling)
        store.applyReview(.again, to: word)
        store.applyReview(.again, to: word)
        XCTAssertTrue(try XCTUnwrap(store.word(withID: word.id)).isStruggling)
        XCTAssertEqual(posts, 1, "announced when it becomes one, not on every lapse")
    }

    func testAMemoryHookComesFromTheProviderOnThisMacOnly() async throws {
        let store = makeStore()
        let enricher = WordEnricher(store: store, cefrEstimator: nil, observesSaves: true)
        var uses: [WordEnricher.ProviderUse] = []
        var onDeviceFields: [FillField] = []
        enricher.backendsOverride = { use in
            uses.append(use)
            return FillBackends(
                dictionary: { _ in nil },
                onDevice: { request in onDeviceFields.append(request.field); return nil },
                provider: (name: "LM Studio", ask: { _ in "Picture a jay that jeers at you from a fence." }),
                level: nil
            )
        }
        var word = SavedWord(term: "jeering", language: Language.english.rawValue)
        word.reviewCount = 3
        word.incorrectCount = 1
        store.add(word)
        store.applyReview(.again, to: try XCTUnwrap(store.word(withID: word.id)))

        for _ in 0..<40 where FillField.mnemonic.isMissing(in: store.word(withID: word.id)!) {
            try await Task.sleep(for: .milliseconds(25))
        }
        let filled = try XCTUnwrap(store.word(withID: word.id))
        XCTAssertEqual(FillField.mnemonic.value(in: filled), "Picture a jay that jeers at you from a fence.")
        XCTAssertEqual(filled.source(of: .mnemonic), .provider("LM Studio"))
        XCTAssertTrue(uses.contains(.onThisMac))
        XCTAssertFalse(uses.contains(.any), "never the cloud unasked")
        XCTAssertFalse(onDeviceFields.contains(.mnemonic), "Apple's model isn't trusted with mnemonics")
        withExtendedLifetime(enricher) {}
    }

    // MARK: Helpers

    private func makeStore() -> SavedWordsStore {
        SavedWordsStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("w.json"))
    }
}
