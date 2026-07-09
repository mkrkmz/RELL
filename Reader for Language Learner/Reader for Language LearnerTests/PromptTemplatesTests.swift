//
//  PromptTemplatesTests.swift
//  Reader for Language LearnerTests
//

import XCTest
@testable import Reader_for_Language_Learner

final class PromptTemplatesTests: XCTestCase {

    func testMeaningModuleSystemPromptFollowsNativeLanguageNotHardcodedTurkish() {
        let german = ModuleType.meaningTR.systemPrompt(customPreamble: "", nativeLanguage: .german)
        XCTAssertTrue(german.contains("Output only in Deutsch."))
        XCTAssertFalse(german.contains("Output only in Turkish."))
    }

    func testMeaningModuleSystemPromptStillTurkishForTurkishNative() {
        let turkish = ModuleType.meaningTR.systemPrompt(customPreamble: "", nativeLanguage: .turkish)
        XCTAssertTrue(turkish.contains("Output only in Türkçe."))
    }

    func testEnglishOnlyModuleIgnoresNativeLanguage() {
        let prompt = ModuleType.definitionEN.systemPrompt(customPreamble: "", nativeLanguage: .japanese)
        XCTAssertTrue(prompt.contains("Output only in English."))
    }

    func testMixedOutputLanguageUnaffectedByNativeLanguageParameter() {
        // Collocations' EN+TR example/translation labels are literal parser
        // targets (ResultParser matches "Örnek Cümle"/"Türkçe Çeviri") —
        // .mixed must stay Turkish-fixed regardless of nativeLanguage.
        let prompt = ModuleType.collocations.systemPrompt(customPreamble: "", nativeLanguage: .french)
        XCTAssertTrue(prompt.contains("TR fields in Turkish only."))
    }
}
