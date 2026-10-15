//
//  CustomModuleTests.swift
//  Reader for Language LearnerTests
//
//  v18 Sprint 3 — the reader's own modules: placeholders filled (and a line
//  without a value left out), the cache forgetting an edited prompt, the
//  store's limits and what it pins, saved answers keeping their name, and
//  the optional Anki sections.
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class CustomModuleTests: XCTestCase {

    private func temporaryStore() -> CustomModuleStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rell-custom-modules-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return CustomModuleStore(fileURL: url)
    }

    private func module(_ name: String = "Quiz", scope: CustomModule.Scope = .word) -> CustomModule {
        CustomModule(name: name, icon: "star", prompt: "Ask about {selection}.", scope: scope)
    }

    // MARK: Placeholders

    func testPlaceholdersAreFilledInEitherLanguage() {
        let values: [CustomPrompt.Placeholder: String] = [
            .selection: "ricochet", .sentence: "It ricocheted.", .book: "Dune",
            .native: "Türkçe", .target: "English", .level: "B2",
        ]
        XCTAssertEqual(CustomPrompt.render("Explain {selection} at {level} in {native}.", values: values),
                       "Explain ricochet at B2 in Türkçe.")
        XCTAssertEqual(CustomPrompt.render("{seçim} — {cümle} ({kitap}, {hedef dil}, {ana dil}, {seviye})", values: values),
                       "ricochet — It ricocheted. (Dune, English, Türkçe, B2)")
    }

    func testALineWithoutAValueIsLeftOut() {
        let prompt = "Explain {selection}.\nThe sentence it came from: {sentence}\nBook: {book}\nAnswer briefly."
        let rendered = CustomPrompt.render(prompt, values: [.selection: "ricochet", .sentence: "  ", .book: "Dune"])
        XCTAssertEqual(rendered, "Explain ricochet.\nBook: Dune\nAnswer briefly.",
                       "a blank sentence drops its whole line, not just the placeholder")
    }

    func testTheSystemPromptFollowsTheAnswerLanguage() {
        var custom = module()
        custom.answerIn = .native
        XCTAssertTrue(CustomPrompt.system(for: custom, native: .turkish, target: .english, preamble: "")
            .contains("Answer in \(Language.turkish.rawValue)."))
        custom.answerIn = .target
        let system = CustomPrompt.system(for: custom, native: .turkish, target: .english, preamble: "Be kind.")
        XCTAssertTrue(system.hasPrefix("Be kind.\n\n"))
        XCTAssertTrue(system.contains("Answer in \(Language.english.rawValue)."))
    }

    // MARK: Cache

    func testEditingWhatShapesTheAnswerChangesTheCacheTag() {
        let original = module()
        let tag = CustomPrompt.cacheTag(original)
        XCTAssertEqual(CustomPrompt.cacheTag(original), tag, "stable for the same module")

        var renamed = original
        renamed.name = "Another name"
        renamed.icon = "flag"
        XCTAssertEqual(CustomPrompt.cacheTag(renamed), tag, "the name and icon don't change the answer")

        var edited = original
        edited.prompt += " Briefly."
        XCTAssertNotEqual(CustomPrompt.cacheTag(edited), tag)
        var longer = original
        longer.length = .long
        XCTAssertNotEqual(CustomPrompt.cacheTag(longer), tag)
        var otherLanguage = original
        otherLanguage.answerIn = .target
        XCTAssertNotEqual(CustomPrompt.cacheTag(otherLanguage), tag)
        var apple = original
        apple.engine = .apple
        XCTAssertNotEqual(CustomPrompt.cacheTag(apple), tag)
    }

    // MARK: Store

    func testANewModuleIsPinnedToTheEndOfTheCardsItRunsOn() {
        let defaults = scratchDefaults()
        let store = temporaryStore()
        let wordOnly = module("Word", scope: .word)
        let both = module("Both", scope: .both)
        XCTAssertTrue(store.add(wordOnly, defaults: defaults))
        XCTAssertTrue(store.add(both, defaults: defaults))

        let word = InspectorCardLayout.load(.word, defaults: defaults, customs: store.modules)
        XCTAssertEqual(Array(word.suffix(2)), [.custom(wordOnly.id), .custom(both.id)])
        XCTAssertEqual(Array(word.prefix(InspectorCardLayout.defaults(.word).count)), InspectorCardLayout.defaults(.word),
                       "the reader's existing card stays as it was")
        let sentence = InspectorCardLayout.load(.sentence, defaults: defaults, customs: store.modules)
        XCTAssertEqual(sentence.last, .custom(both.id))
        XCTAssertFalse(sentence.contains(.custom(wordOnly.id)), "a word module isn't offered for a sentence")
    }

    func testTheStoreKeepsItsLimits() {
        let defaults = scratchDefaults()
        let store = temporaryStore()
        var long = module()
        long.prompt = String(repeating: "x", count: CustomModule.maxPromptLength + 50)
        XCTAssertTrue(store.add(long, defaults: defaults))
        XCTAssertEqual(store.modules.first?.prompt.count, CustomModule.maxPromptLength)

        for index in 1..<CustomModule.maxCount {
            XCTAssertTrue(store.add(module("M\(index)"), defaults: defaults))
        }
        XCTAssertEqual(store.modules.count, CustomModule.maxCount)
        XCTAssertFalse(store.canAdd)
        XCTAssertFalse(store.add(module("One too many"), defaults: defaults))
        XCTAssertEqual(store.modules.count, CustomModule.maxCount)
    }

    func testModulesSurviveARelaunchAndDeleteRemovesThem() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rell-custom-modules-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let defaults = scratchDefaults()
        let store = CustomModuleStore(fileURL: url)
        var custom = module()
        store.add(custom, defaults: defaults)
        custom.name = "Renamed"
        store.update(custom)

        XCTAssertEqual(CustomModuleStore(fileURL: url).modules, [custom])
        store.delete(custom.id)
        XCTAssertEqual(CustomModuleStore(fileURL: url).modules, [])
        XCTAssertFalse(InspectorCardLayout.load(.word, defaults: defaults, customs: store.modules).contains(.custom(custom.id)),
                       "a deleted module leaves the card")
    }

    func testSavingFromTheEditorAddsANewModuleAndUpdatesAnExistingOne() {
        let defaults = scratchDefaults()
        let store = temporaryStore()
        var custom = module("First")
        XCTAssertTrue(store.save(custom, defaults: defaults), "a module not in the list yet is added, never dropped")
        XCTAssertEqual(store.modules.map(\.name), ["First"])
        XCTAssertTrue(InspectorCardLayout.load(.word, defaults: defaults, customs: store.modules).contains(.custom(custom.id)))

        custom.name = "Renamed"
        XCTAssertTrue(store.save(custom, defaults: defaults))
        XCTAssertEqual(store.modules.map(\.name), ["Renamed"], "the same id is updated, not added twice")
    }

    // MARK: Card ids

    func testACustomItemsIdRoundTrips() {
        let id = UUID()
        XCTAssertEqual(CardItem.custom(id).id, "custom.\(id.uuidString)")
        XCTAssertEqual(CardItem(id: CardItem.custom(id).id), .custom(id))
        XCTAssertFalse(CardItem.custom(id).isAction)
    }

    // MARK: Saved answers

    func testSavedAnswersKeepTheirNameAfterTheModuleIsGone() {
        let kept = module("Quiz Me")
        let goneID = UUID()
        let outputs = [
            ModuleType.definitionEN.rawValue: "a rebound",
            CustomModule.outputKey(goneID): "An old answer",
            CustomModule.titleKey(goneID): "Formal / Casual",
            CustomModule.outputKey(kept.id): "Three questions",
            CustomModule.titleKey(kept.id): "Old name",
            CustomModule.outputKey(UUID()): "   ",
        ]
        let answers = CustomPrompt.savedAnswers(in: outputs, modules: [kept])
        XCTAssertEqual(answers.map(\.title), ["Quiz Me", "Formal / Casual"],
                       "a module you still have shows its current name first; an empty answer is skipped")
        XCTAssertEqual(answers.map(\.body), ["Three questions", "An old answer"])
    }

    func testAnOwnModulesNameIsNeverACardsDefinition() {
        let id = UUID()
        let word = SavedWord(term: "ricochet", sentence: "It ricocheted.",
                             llmOutputs: [CustomModule.titleKey(id): "Quiz Me"])
        XCTAssertEqual(word.reviewDefinition, "It ricocheted.")
    }

    // MARK: Anki

    func testOwnAnswersGoAfterTheBuiltInModules() {
        let note = AnkiExporter.buildNote(
            selectedText: "ricochet", mode: .word, domain: .general,
            selectedModules: [.definitionEN], outputs: [.definitionEN: "a rebound"],
            includeSource: false, pdfFilename: nil, pageNumber: nil, tags: "rell",
            ownAnswers: [OwnModuleAnswer(id: UUID(), title: "Quiz Me", body: "Three questions"),
                         OwnModuleAnswer(id: UUID(), title: "Empty", body: " ")]
        )
        let definition = try? XCTUnwrap(note.back.range(of: "a rebound"))
        let own = try? XCTUnwrap(note.back.range(of: "<b>[Quiz Me]</b><br>Three questions"))
        XCTAssertNotNil(definition)
        XCTAssertNotNil(own)
        if let definition, let own { XCTAssertLessThan(definition.lowerBound, own.lowerBound) }
        XCTAssertFalse(note.back.contains("[Empty]"))

        let without = AnkiExporter.buildNote(
            selectedText: "ricochet", mode: .word, domain: .general,
            selectedModules: [.definitionEN], outputs: [.definitionEN: "a rebound"],
            includeSource: false, pdfFilename: nil, pageNumber: nil, tags: "rell"
        )
        XCTAssertFalse(without.back.contains("Quiz Me"), "off unless asked for")
    }
}
