//
//  WordFillTests.swift
//  Reader for Language LearnerTests
//
//  v15 Sprint 1 — filling saved words' empty card fields: reading a macOS
//  dictionary entry, the source order, never writing over a value, Stop,
//  the save-time fill staying off the cloud, and old files still opening.
//

import SwiftUI
import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class WordFillTests: XCTestCase {

    // Entries as the user's Mac returned them in S0 (English–Turkish first,
    // Oxford English for words it lacks).
    private let manure = "manure | məˈnjυə(r) | n hayvan gübresi "
    private let loll = "loll | lɒl | intransitive verb tembel tembel oturmak "
    private let gleam = "gleam | ɡliːm | n ışık; parıltı intransitive verb parlamak; parıldamak "
    private let sleep = "sleep | sliːp | n uyku ▸ go to sleep uyumak ▸ put to sleep acıyarak öldürmek intransitive verb past participle, past slept uyumak "
    private let archEnemy = "arch-enemy | ˌɑːtʃˈɛnɪmi | noun a person who is extremely opposed or hostile to someone or something: the twins were arch-enemies. • (the arch-enemy) archaic the Devil. "
    private let absentMinded = "absent-minded | ˌabs(ə)ntˈmʌɪndɪd | adjective having or showing a forgetful or inattentive disposition: an absent-minded smile. DERIVATIVES absent-mindedly | absəntˈmʌɪndɪdli | adverb "

    // MARK: Dictionary entries

    func testBilingualEntriesGiveTheFirstSensesWithoutGrammar() async {
        XCTAssertEqual(DictionaryEntry(raw: manure)?.briefSenses, "hayvan gübresi")
        XCTAssertEqual(DictionaryEntry(raw: loll)?.briefSenses, "tembel tembel oturmak")
        XCTAssertEqual(DictionaryEntry(raw: gleam)?.briefSenses, "ışık; parıltı", "only the first part of speech")
        XCTAssertEqual(DictionaryEntry(raw: sleep)?.briefSenses, "uyku", "phrases after ▸ are dropped")
    }

    /// v15 S1 live pass: an entry with no pronunciation bars gave the word
    /// itself as its Turkish meaning.
    func testEntriesWithoutBarsFindTheirHeadword() async throws {
        let entry = try XCTUnwrap(DictionaryEntry(raw: "brainwave n (ani bir) parlak fikir; ilham brain "))
        XCTAssertEqual(entry.headword, "brainwave")
        XCTAssertNil(entry.ipa)
        XCTAssertEqual(entry.briefSenses, "(ani bir) parlak fikir; ilham", "the trailing cross-reference goes")
        XCTAssertEqual(DictionaryEntry(raw: sleep + "sleeper sleepless sleepwalking")?.body.hasSuffix("uyumak"), true)
    }

    func testThesaurusEntriesAnswerNothing() async {
        let entry = DictionaryEntry(raw: "untimely adjective 1 I would like to explain the untimely interruption. ill-timed, badly timed, mistimed; inopportune, inappropriate; inconvenient, awkward. ANTONYMS timely, opportune.")
        XCTAssertEqual(entry?.isThesaurus, true)
        XCTAssertNil(entry?.briefSenses, "an example and synonyms are not a definition")
    }

    func testLabelsBeforeThePartOfSpeechAndAloneArePassedOver() async {
        XCTAssertEqual(DictionaryEntry(raw: "teammate | ˈtiːmmeɪt | (also team mate) noun a fellow member of a team: we're good friends. ")?.briefSenses,
                       "a fellow member of a team")
        XCTAssertNil(DictionaryEntry(raw: "jeer | dʒiə(r) | intransitive verb ▸ jeer at alaya almak yuhalamak ")?.briefSenses,
                     "only a part of speech before the phrases")
        XCTAssertEqual(DictionaryEntry(raw: "flat | flæt | adj flatterflattest1 düz; yassı 2 surface düz; dümdüz 3 refusal kesin ")?.senses.first,
                       "düz; yassı", "the inflections glued to the sense number go")
    }

    /// Bilingual entries label senses in the language you study: "2 mock
    /// alay etmek", "2 state durum". Short native words ("kat") stay.
    func testSenseLabelsInTheStudiedLanguageAreDropped() async {
        let english: Set<String> = ["mock", "state", "before", "prove", "to", "be", "kat", "surface"]
        func meaning(_ raw: String, _ term: String) -> String? {
            WordFillEngine.dictionaryAnswer(for: term, raw: raw, native: .turkish, target: .english,
                                            isTargetWord: { english.contains($0.lowercased()) })[.meaning]
        }
        XCTAssertEqual(meaning("sneer | sniə(r) | intransitive verb 1 dudak bükerek gülmek 2 mock alay etmek ", "sneered"),
                       "dudak bükerek gülmek; alay etmek")
        XCTAssertEqual(meaning("prove | pruːv | transitive verb kanıtlamak; ispat etmek prove to be ", "proven"),
                       "kanıtlamak; ispat etmek")
        XCTAssertEqual(meaning("storey | ˈstɔːri | n kat; bina katı ", "storey"), "kat; bina katı")
        XCTAssertEqual(meaning("flat | flæt | adj flatterflattest1 düz; yassı 2 surface düz; dümdüz ", "flats"),
                       "düz; yassı; dümdüz")
    }

    func testTheWordItselfIsNeverItsMeaning() async {
        let answer = WordFillEngine.dictionaryAnswer(for: "brainwave", raw: "brainwave n brainwave ",
                                                     native: .turkish, target: .english)
        XCTAssertNil(answer[.meaning])
        XCTAssertNil(answer[.definition])
    }

    /// v15 S1 live pass: asked with the book sentence as context, the model
    /// wrote the sentence's translation as the Turkish meaning.
    func testRepairEmptiesWhatTheContextPromptWroteAndNothingElse() async throws {
        let store = makeStore()
        let translated = SavedWord(term: "savagely", sentence: "he thought savagely as he spread manure",
                                   llmOutputs: [ModuleType.meaningTR.rawValue: "\"Ünlü Harry Potter'ı şimdi görebilmeyi dilerlerdi.\""],
                                   language: Language.english.rawValue,
                                   fieldSources: ["meaning": FillSource.provider("LM Studio").stored])
        let noSentence = SavedWord(term: "lawn", llmOutputs: [ModuleType.definitionEN.rawValue: "An area of short grass."],
                                   language: Language.english.rawValue,
                                   fieldSources: ["definition": FillSource.onDevice.stored])
        let yours = SavedWord(term: "landlady", sentence: "He owed his landlady money.",
                              llmOutputs: [ModuleType.meaningTR.rawValue: "ev sahibesi"])
        for word in [translated, noSentence, yours] { store.add(word) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "WordFillTests-\(UUID().uuidString)"))
        let enricher = WordEnricher(store: store, cefrEstimator: nil, observesSaves: false)

        // Version 2 ran on the live-pass Mac with half the fixes; 3 runs again.
        defaults.set(2, forKey: StorageKey.fillRepairVersion)
        XCTAssertEqual(enricher.repairEarlierFills(defaults: defaults), 1)

        XCTAssertTrue(FillField.meaning.isMissing(in: try XCTUnwrap(store.word(withID: translated.id))))
        XCTAssertNil(store.word(withID: translated.id)?.source(of: .meaning))
        XCTAssertEqual(store.word(withID: noSentence.id)?.llmOutputs, noSentence.llmOutputs, "no context was sent for it")
        XCTAssertEqual(store.word(withID: yours.id)?.llmOutputs, yours.llmOutputs, "no source mark: yours, untouched")
        XCTAssertEqual(defaults.integer(forKey: StorageKey.fillStripHiddenAtCount), -1, "the strip comes back")
        XCTAssertEqual(enricher.repairEarlierFills(defaults: defaults), 0, "runs once")
    }

    func testMonolingualEntriesDropExamplesAndDerivatives() async {
        XCTAssertEqual(DictionaryEntry(raw: archEnemy)?.briefSenses,
                       "a person who is extremely opposed or hostile to someone or something; (the arch-enemy) archaic the Devil")
        XCTAssertEqual(DictionaryEntry(raw: absentMinded)?.briefSenses,
                       "having or showing a forgetful or inattentive disposition")
        XCTAssertEqual(DictionaryEntry(raw: "sleep | sliːp | noun 1 a condition of rest: I need some sleep. 2 a gummy secretion. ")?.briefSenses,
                       "a condition of rest; a gummy secretion")
    }

    func testPronunciationNamesTheBaseFormForOtherForms() async {
        XCTAssertEqual(DictionaryEntry(raw: manure)?.pronunciation(for: "manure"), "/məˈnjυə(r)/")
        XCTAssertEqual(DictionaryEntry(raw: archEnemy)?.pronunciation(for: "archenemy"), "/ˌɑːtʃˈɛnɪmi/",
                       "a hyphen doesn't make another word")
        XCTAssertEqual(DictionaryEntry(raw: loll)?.pronunciation(for: "lolled"), "/lɒl/ (loll)",
                       "another form gets the base form's, named")
    }

    // MARK: Validation

    func testModelAnswersThatAreNoAnswerAreRejected() async {
        func ok(_ text: String, _ field: FillField = .definition, _ language: Language = .english) -> String? {
            FillValidator.accept(text, term: "manure", language: language, field: field)
        }
        XCTAssertNil(ok("   "))
        XCTAssertNil(ok("Manure"), "the word repeated back")
        XCTAssertNil(ok("I am a foundation model and cannot help with that."))
        XCTAssertNil(ok("Animal dung that farmers spread on fields to feed the soil.", .meaning, .turkish),
                     "a meaning in the wrong language")
        XCTAssertEqual(ok("gübre", .meaning, .turkish), "gübre", "too short to judge the language")
        XCTAssertEqual(ok("Animal dung used for fertilizing land."), "Animal dung used for fertilizing land.")
    }

    // MARK: Source order

    func testDictionaryFirstThenOnDeviceThenProvider() async {
        var asked: [String] = []
        let backends = FillBackends(
            dictionary: { [manure] _ in manure },
            onDevice: { request in
                asked.append("device-\(request.field.rawValue)")
                return request.field == .definition ? "" : "unused"   // empty: not usable
            },
            provider: (name: "LM Studio", ask: { request in
                asked.append("provider-\(request.field.rawValue)")
                return "Animal dung used for fertilizing land."
            }),
            level: nil
        )
        let results = await fill(SavedWord(term: "manure", language: Language.english.rawValue),
                                 [.meaning, .definition, .pronunciation], backends)

        XCTAssertEqual(results, [
            FillResult(field: .meaning, value: "hayvan gübresi", source: .dictionary),
            FillResult(field: .definition, value: "Animal dung used for fertilizing land.", source: .provider("LM Studio")),
            FillResult(field: .pronunciation, value: "/məˈnjυə(r)/", source: .dictionary),
        ])
        XCTAssertEqual(asked, ["device-definition", "provider-definition"],
                       "the dictionary answered the meaning; the models were asked only for the definition")
    }

    func testFilledFieldsAreNotAskedFor() async {
        var asked = 0
        let word = SavedWord(term: "manure", llmOutputs: [ModuleType.meaningTR.rawValue: "gübre"], cefrLevel: "B2",
                             language: Language.english.rawValue)
        let backends = FillBackends(
            dictionary: { _ in nil },
            onDevice: { _ in asked += 1; return "Animal dung used for fertilizing land." },
            provider: nil,
            level: { _ in asked += 1; return nil }
        )
        let results = await fill(word, Set(FillField.allCases).subtracting([.examples]), backends)
        XCTAssertEqual(results.map(\.field), [.definition])
        XCTAssertEqual(asked, 1)
    }

    func testNothingFoundWritesNothing() async {
        let backends = FillBackends(dictionary: { _ in nil }, onDevice: { _ in "" }, provider: nil, level: nil)
        let results = await fill(SavedWord(term: "zyx", language: Language.english.rawValue), FillField.defaultSelection, backends)
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: Store

    func testFillNeverWritesOverAValue() async throws {
        let store = makeStore()
        let word = SavedWord(term: "manure", llmOutputs: [ModuleType.meaningTR.rawValue: "gübre (mine)"])
        store.add(word)

        XCTAssertFalse(store.fill(.meaning, with: "hayvan gübresi", source: .dictionary, forWordID: word.id))
        XCTAssertTrue(store.fill(.definition, with: "Animal dung.", source: .onDevice, forWordID: word.id))
        XCTAssertTrue(store.fill(.level, with: "C1", source: .onDevice, forWordID: word.id))
        XCTAssertFalse(store.fill(.level, with: "A1", source: .onDevice, forWordID: word.id))

        let saved = try XCTUnwrap(store.word(withID: word.id))
        XCTAssertEqual(saved.llmOutputs[ModuleType.meaningTR.rawValue], "gübre (mine)")
        XCTAssertNil(saved.source(of: .meaning), "yours has no source mark")
        XCTAssertEqual(saved.source(of: .definition), .onDevice)
        XCTAssertEqual(saved.cefrLevel, "C1")
        XCTAssertTrue(saved.cefrIsAuto)

        store.setCEFRLevel(.b2, for: saved)
        XCTAssertNil(store.word(withID: word.id)?.source(of: .level), "a level you set is yours")
        store.clear(.definition, forWordID: word.id)
        XCTAssertTrue(FillField.definition.isMissing(in: try XCTUnwrap(store.word(withID: word.id))))
        XCTAssertNil(store.word(withID: word.id)?.source(of: .definition))
    }

    func testOldFilesOpenAndSourcesRoundTrip() async throws {
        let old = #"[{"id":"\#(UUID().uuidString)","term":"landlady","llmOutputs":{"meaningTR":"ev sahibesi"}}]"#
        let decoded = try JSONDecoder().decode([SavedWord].self, from: Data(old.utf8))
        XCTAssertEqual(decoded.first?.fieldSources, [:])

        var word = SavedWord(term: "manure", fieldSources: ["meaning": FillSource.dictionary.stored,
                                                            "definition": FillSource.provider("LM Studio").stored])
        word.llmOutputs = [:]
        let again = try JSONDecoder().decode(SavedWord.self, from: JSONEncoder().encode(word))
        XCTAssertEqual(again.source(of: .meaning), .dictionary)
        XCTAssertEqual(again.source(of: .definition), .provider("LM Studio"))
    }

    // MARK: Bulk run

    func testBulkRunFillsAndCountsBySource() async throws {
        let store = makeStore()
        for term in ["manure", "gleam", "zyx"] { store.add(SavedWord(term: term, language: Language.english.rawValue)) }
        let enricher = WordEnricher(store: store, cefrEstimator: nil, observesSaves: false)
        enricher.backendsOverride = { [manure, gleam] _ in
            FillBackends(
                dictionary: { ["manure": manure, "gleam": gleam][$0] },
                onDevice: { $0.field == .definition ? "A clear short definition of the word." : nil },
                provider: nil, level: nil
            )
        }
        XCTAssertEqual(enricher.missingCount(.meaning), 3)

        enricher.start(fields: [.meaning, .definition], allowProvider: false)
        let run = try await finished(enricher)

        XCTAssertEqual(run.completed, 3)
        XCTAssertEqual(run.count(.meaning, .dictionary), 2)
        XCTAssertEqual(run.count(.definition, .model), 3)
        XCTAssertEqual(run.filledCount, 5)
        XCTAssertEqual(enricher.missingCount(.meaning), 1, "zyx isn't in the dictionary")
    }

    func testStopKeepsWhatWasFilledAndDoesNoMore() async throws {
        let store = makeStore()
        for term in ["one", "two", "three"] { store.add(SavedWord(term: term, language: Language.english.rawValue)) }
        let enricher = WordEnricher(store: store, cefrEstimator: nil, observesSaves: false)
        var asked: [String] = []
        enricher.backendsOverride = { _ in
            FillBackends(dictionary: { _ in nil }, onDevice: { request in
                asked.append(request.term)
                enricher.stop()   // stop during the first word
                return "A definition that is long enough to keep."
            }, provider: nil, level: nil)
        }
        enricher.start(fields: [.definition], allowProvider: false)
        let run = try await finished(enricher)

        XCTAssertTrue(run.wasStopped)
        XCTAssertEqual(asked.count, 1, "no word after Stop")
        XCTAssertEqual(enricher.missingCount(.definition), 2, "the answer in flight still lands")
    }

    func testTheSaveTimeFillStaysOffTheCloudAndLeavesTheLevel() async throws {
        let store = makeStore()
        let enricher = WordEnricher(store: store, cefrEstimator: nil, observesSaves: true)
        var uses: [WordEnricher.ProviderUse] = []
        var levelAsked = false
        enricher.backendsOverride = { [manure] use in
            uses.append(use)
            return FillBackends(dictionary: { _ in manure }, onDevice: nil, provider: nil,
                                level: { _ in levelAsked = true; return nil })
        }
        let word = SavedWord(term: "manure", language: Language.english.rawValue)
        store.add(word)

        for _ in 0..<40 where FillField.meaning.isMissing(in: store.word(withID: word.id)!) {
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertEqual(store.word(withID: word.id)?.llmOutputs[ModuleType.meaningTR.rawValue], "hayvan gübresi")
        XCTAssertEqual(uses, [.onThisMac])
        XCTAssertFalse(levelAsked, "the CEFR estimator already does the level at save time")
        withExtendedLifetime(enricher) {}
    }

    func testOnlyALocalServerCountsAsOnThisMac() async {
        func check(_ type: LLMProviderType, _ url: String, _ model: String) -> Bool {
            WordEnricher.runsOnThisMac(type: type, serverURL: url, model: model)
        }
        XCTAssertTrue(check(.lmStudio, "http://127.0.0.1:1234", "google/gemma-4-e4b"))
        XCTAssertTrue(check(.ollama, "http://localhost:11434", "gemma3:4b"))
        XCTAssertFalse(check(.ollama, "http://127.0.0.1:11434", "gemma4:31b-cloud"), "Ollama cloud models run remotely")
        XCTAssertFalse(check(.lmStudio, "http://192.168.1.20:1234", "gemma"))
        XCTAssertFalse(check(.anthropic, "https://api.anthropic.com", "claude-opus-5"))
    }

    // MARK: Layout

    /// The strip sits in the sidebar column: at the narrowest width it stays
    /// one compact block instead of pushing the window taller.
    func testStripFitsTheNarrowestSidebar() async throws {
        let store = makeStore()
        for term in ["archenemy", "absent-mindedly", "anatomically"] { store.add(SavedWord(term: term)) }
        let enricher = WordEnricher(store: store, cefrEstimator: nil, observesSaves: false)
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: StorageKey.fillStripHiddenAtCount)
        defaults.set(-1, forKey: StorageKey.fillStripHiddenAtCount)
        defer { defaults.set(previous, forKey: StorageKey.fillStripHiddenAtCount) }

        let strip = VStack(spacing: 0) { FillMissingStrip(enricher: enricher) {}; Spacer(minLength: 0) }
        let height = try await LayoutGuard.settledHeight(of: strip, width: 184, height: 60)
        XCTAssertLessThanOrEqual(height, 60 + 1, "the strip forced the window to \(height) pt")
    }

    // MARK: Helpers

    private func fill(_ word: SavedWord, _ fields: Set<FillField>, _ backends: FillBackends) async -> [FillResult] {
        var results: [FillResult] = []
        await WordFillEngine.fill(word, fields: fields, backends: backends, native: .turkish) { results.append($0) }
        return results
    }

    private func makeStore() -> SavedWordsStore {
        SavedWordsStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("w.json"))
    }

    private func finished(_ enricher: WordEnricher) async throws -> WordEnricher.Run {
        for _ in 0..<200 where enricher.run?.isFinished != true {
            try await Task.sleep(for: .milliseconds(10))
        }
        return try XCTUnwrap(enricher.run?.isFinished == true ? enricher.run : nil, "the run didn't finish")
    }
}
