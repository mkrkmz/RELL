//
//  PromptTemplatesTests.swift
//  Reader for Language LearnerTests
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class PromptTemplatesTests: XCTestCase {

    // MARK: - Native language (meaning module)

    func testMeaningModuleSystemPromptFollowsNativeLanguageNotHardcodedTurkish() async {
        let german = ModuleType.meaningTR.systemPrompt(customPreamble: "", nativeLanguage: .german, targetLanguage: .english)
        XCTAssertTrue(german.contains("Output only in Deutsch."))
        XCTAssertFalse(german.contains("Output only in Turkish."))
    }

    func testMeaningModuleSystemPromptStillTurkishForTurkishNative() async {
        let turkish = ModuleType.meaningTR.systemPrompt(customPreamble: "", nativeLanguage: .turkish, targetLanguage: .english)
        XCTAssertTrue(turkish.contains("Output only in Türkçe."))
        XCTAssertTrue(turkish.contains("\"Bilinmiyor\""))
    }

    // MARK: - Target language (explanation modules)

    func testTargetModuleFollowsTargetLanguage() async {
        let prompt = ModuleType.definitionEN.systemPrompt(customPreamble: "", nativeLanguage: .turkish, targetLanguage: .german)
        XCTAssertTrue(prompt.contains("Output only in Deutsch."))
        XCTAssertTrue(prompt.contains("\"Unbekannt\""))
    }

    func testTargetModuleIgnoresNativeLanguage() async {
        let prompt = ModuleType.definitionEN.systemPrompt(customPreamble: "", nativeLanguage: .japanese, targetLanguage: .english)
        XCTAssertTrue(prompt.contains("Output only in English."))
    }

    func testDefinitionUserPromptNamesTargetLanguage() async {
        let word = ModuleType.definitionEN.userPrompt(
            term: "Haus", mode: .word, detail: .short,
            nativeLanguage: .turkish, targetLanguage: .german
        )
        XCTAssertTrue(word.contains("Define it in German, like a learner's dictionary"))

        let sentence = ModuleType.definitionEN.userPrompt(
            term: "Das ist ein Haus.", mode: .sentence, detail: .short,
            nativeLanguage: .turkish, targetLanguage: .german
        )
        XCTAssertTrue(sentence.contains("in plain German."))
    }

    // MARK: - Golden strings: English-target prompts must not drift
    // (regression safety for existing EN-target users — the prompt text below
    // is pinned byte-for-byte; a deliberate prompt change must update these).

    func testGoldenEnglishTargetSystemPrompt() async {
        let prompt = ModuleType.definitionEN.systemPrompt(customPreamble: "", nativeLanguage: .turkish, targetLanguage: .english)
        XCTAssertEqual(prompt, """
        You are a dictionary assistant for language learners.
        Output only in English.
        Plain text only.
        Answer directly and compactly — no preamble, no commentary, no code fences.
        If unsure, write "Unknown".
        """)
    }

    /// Revision 2 (v19 S1): learner's-dictionary style, the reader's level.
    func testGoldenEnglishTargetDefinitionUserPrompt() async {
        let prompt = ModuleType.definitionEN.userPrompt(
            term: "orbit", mode: .word, detail: .short,
            nativeLanguage: .turkish, targetLanguage: .english, level: .b1
        )
        XCTAssertEqual(prompt, """
        Word/Phrase: orbit

        Define it in English, like a learner's dictionary: start with the part of speech in brackets, e.g. (verb), then plain words.
        The reader is a B1 learner of English: use words a B1 learner knows.
        Write one sentence for the main meaning.
        """)
    }

    // MARK: - Revision 2 (v19 S1)

    func testWordModulesAnswerForTheSenseInTheSentence() async {
        let sentence = "They sat on the bank of the river."
        for module in [ModuleType.examplesEN, .collocations, .synonymsEN, .wordFamilyEN, .mnemonicEN, .usageNotesEN] {
            let prompt = module.userPrompt(term: "bank", mode: .word, detail: .short, context: sentence,
                                           nativeLanguage: .turkish, targetLanguage: .english, level: .b1)
            XCTAssertTrue(prompt.contains(sentence), "\(module.rawValue) doesn't see the sentence")
            XCTAssertTrue(prompt.contains("Use the sense the word has in the context sentence."), module.rawValue)
            XCTAssertTrue(module.usesContext(mode: .word), "\(module.rawValue): its answer depends on the sentence")
        }
        XCTAssertFalse(ModuleType.examplesEN.usesContext(mode: .sentence))
    }

    func testAPromptWithoutASentenceDoesNotMentionOne() async {
        let prompt = ModuleType.examplesEN.userPrompt(term: "bank", mode: .word, detail: .short, context: "  ",
                                                     nativeLanguage: .turkish, targetLanguage: .english, level: .b1)
        XCTAssertFalse(prompt.contains("context sentence"), "a blank sentence counts as none")
    }

    func testTheMemoryHookIsInYourLanguage() async {
        guard case .native(let language) = ModuleType.mnemonicEN.outputLanguage(nativeLanguage: .turkish, targetLanguage: .english) else {
            return XCTFail("the hook uses a sound-alike in your language")
        }
        XCTAssertEqual(language, .turkish)
        let prompt = ModuleType.mnemonicEN.userPrompt(term: "actual", mode: .word, detail: .short,
                                                      nativeLanguage: .turkish, targetLanguage: .english, level: .b1)
        XCTAssertTrue(prompt.contains("sounds like \"actual\""))
        XCTAssertEqual(FillRequest(field: .mnemonic, term: "actual", sentence: "", native: .turkish, target: .english).answerLanguage,
                       .turkish, "Fill Missing checks the hook's language too")
    }

    func testTheLevelReachesTheModulesThatExplain() async {
        for module in [ModuleType.definitionEN, .examplesEN] {
            let prompt = module.userPrompt(term: "bank", mode: .word, detail: .short,
                                           nativeLanguage: .turkish, targetLanguage: .english, level: .a2)
            XCTAssertTrue(prompt.contains("A2 learner"), module.rawValue)
        }
    }

    // MARK: - Collocations (.mixed): English structural labels, localized content

    func testCollocationLabelsStayEnglishForAllNativeLanguages() async {
        for native in Language.allCases {
            let prompt = ModuleType.collocations.userPrompt(
                term: "orbit", mode: .word, detail: .short,
                nativeLanguage: native, targetLanguage: .english
            )
            XCTAssertTrue(prompt.contains("*Example:*"), "\(native.rawValue) lost the Example parser label")
            XCTAssertTrue(prompt.contains("*Translation:*"), "\(native.rawValue) lost the Translation parser label")
            XCTAssertFalse(prompt.contains("Örnek Cümle"), "\(native.rawValue) still has legacy Turkish label")
            XCTAssertFalse(prompt.contains("Türkçe Çeviri"), "\(native.rawValue) still has legacy Turkish label")
        }
    }

    func testCollocationPromptRequestsNativeLanguageContent() async {
        let prompt = ModuleType.collocations.userPrompt(
            term: "orbit", mode: .word, detail: .short,
            nativeLanguage: .german, targetLanguage: .english
        )
        XCTAssertTrue(prompt.contains("meaning in German, German only"))
        XCTAssertTrue(prompt.contains("[German translation of the example]"))
        XCTAssertFalse(prompt.lowercased().contains("turkish"))
    }

    func testMixedSystemPromptNamesBothLanguages() async {
        let prompt = ModuleType.collocations.systemPrompt(customPreamble: "", nativeLanguage: .french, targetLanguage: .german)
        XCTAssertTrue(prompt.contains("Example sentences in German only."))
        XCTAssertTrue(prompt.contains("Meanings and translations in French only."))
        XCTAssertFalse(prompt.contains("TR fields"))
    }

    // MARK: - Usage notes: machine labels never localized

    func testUsageNotesLabelsStayEnglishMachineTokens() async {
        let prompt = ModuleType.usageNotesEN.userPrompt(
            term: "orbit", mode: .word, detail: .detailed,
            nativeLanguage: .japanese, targetLanguage: .german
        )
        for label in ["FREQ:", "REG:", "CONFUSE:", "CAUTION:"] {
            XCTAssertTrue(prompt.contains(label), "missing machine label \(label)")
        }
    }
}
