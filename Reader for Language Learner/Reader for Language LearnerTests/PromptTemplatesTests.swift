//
//  PromptTemplatesTests.swift
//  Reader for Language LearnerTests
//

import XCTest
@testable import Reader_for_Language_Learner

final class PromptTemplatesTests: XCTestCase {

    // MARK: - Native language (meaning module)

    func testMeaningModuleSystemPromptFollowsNativeLanguageNotHardcodedTurkish() {
        let german = ModuleType.meaningTR.systemPrompt(customPreamble: "", nativeLanguage: .german, targetLanguage: .english)
        XCTAssertTrue(german.contains("Output only in Deutsch."))
        XCTAssertFalse(german.contains("Output only in Turkish."))
    }

    func testMeaningModuleSystemPromptStillTurkishForTurkishNative() {
        let turkish = ModuleType.meaningTR.systemPrompt(customPreamble: "", nativeLanguage: .turkish, targetLanguage: .english)
        XCTAssertTrue(turkish.contains("Output only in Türkçe."))
        XCTAssertTrue(turkish.contains("\"Bilinmiyor\""))
    }

    // MARK: - Target language (explanation modules)

    func testTargetModuleFollowsTargetLanguage() {
        let prompt = ModuleType.definitionEN.systemPrompt(customPreamble: "", nativeLanguage: .turkish, targetLanguage: .german)
        XCTAssertTrue(prompt.contains("Output only in Deutsch."))
        XCTAssertTrue(prompt.contains("\"Unbekannt\""))
    }

    func testTargetModuleIgnoresNativeLanguage() {
        let prompt = ModuleType.definitionEN.systemPrompt(customPreamble: "", nativeLanguage: .japanese, targetLanguage: .english)
        XCTAssertTrue(prompt.contains("Output only in English."))
    }

    func testDefinitionUserPromptNamesTargetLanguage() {
        let word = ModuleType.definitionEN.userPrompt(
            term: "Haus", mode: .word, detail: .short,
            nativeLanguage: .turkish, targetLanguage: .german
        )
        XCTAssertTrue(word.contains("Define it in German."))

        let sentence = ModuleType.definitionEN.userPrompt(
            term: "Das ist ein Haus.", mode: .sentence, detail: .short,
            nativeLanguage: .turkish, targetLanguage: .german
        )
        XCTAssertTrue(sentence.contains("in plain German."))
    }

    // MARK: - Golden strings: English-target prompts must not drift
    // (regression safety for existing EN-target users — the prompt text below
    // is pinned byte-for-byte; a deliberate prompt change must update these).

    func testGoldenEnglishTargetSystemPrompt() {
        let prompt = ModuleType.definitionEN.systemPrompt(customPreamble: "", nativeLanguage: .turkish, targetLanguage: .english)
        XCTAssertEqual(prompt, """
        You are a dictionary assistant for language learners.
        Output only in English.
        Plain text only.
        Answer directly and compactly — no preamble, no commentary, no code fences.
        If unsure, write "Unknown".
        """)
    }

    func testGoldenEnglishTargetDefinitionUserPrompt() {
        let prompt = ModuleType.definitionEN.userPrompt(
            term: "orbit", mode: .word, detail: .short,
            nativeLanguage: .turkish, targetLanguage: .english
        )
        XCTAssertEqual(prompt, """
        Word/Phrase: orbit

        Define it in English.
        Write 1 short paragraph.
        """)
    }

    // MARK: - Collocations (.mixed): English structural labels, localized content

    func testCollocationLabelsStayEnglishForAllNativeLanguages() {
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

    func testCollocationPromptRequestsNativeLanguageContent() {
        let prompt = ModuleType.collocations.userPrompt(
            term: "orbit", mode: .word, detail: .short,
            nativeLanguage: .german, targetLanguage: .english
        )
        XCTAssertTrue(prompt.contains("meaning in German, German only"))
        XCTAssertTrue(prompt.contains("[German translation of the example]"))
        XCTAssertFalse(prompt.lowercased().contains("turkish"))
    }

    func testMixedSystemPromptNamesBothLanguages() {
        let prompt = ModuleType.collocations.systemPrompt(customPreamble: "", nativeLanguage: .french, targetLanguage: .german)
        XCTAssertTrue(prompt.contains("Example sentences in German only."))
        XCTAssertTrue(prompt.contains("Meanings and translations in French only."))
        XCTAssertFalse(prompt.contains("TR fields"))
    }

    // MARK: - Usage notes: machine labels never localized

    func testUsageNotesLabelsStayEnglishMachineTokens() {
        let prompt = ModuleType.usageNotesEN.userPrompt(
            term: "orbit", mode: .word, detail: .detailed,
            nativeLanguage: .japanese, targetLanguage: .german
        )
        for label in ["FREQ:", "REG:", "CONFUSE:", "CAUTION:"] {
            XCTAssertTrue(prompt.contains(label), "missing machine label \(label)")
        }
    }
}
