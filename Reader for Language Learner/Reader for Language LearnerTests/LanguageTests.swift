//
//  LanguageTests.swift
//  Reader for Language LearnerTests
//

import XCTest
@testable import Reader_for_Language_Learner

final class LanguageTests: XCTestCase {

    func testAllCasesCount() {
        XCTAssertEqual(Language.allCases.count, 12)
    }

    func testRawValueRoundTrip() {
        for lang in Language.allCases {
            XCTAssertEqual(Language(rawValue: lang.rawValue), lang)
        }
    }

    func testCodableRoundTrip() throws {
        let original = Language.japanese
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Language.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testFlagIsNotEmpty() {
        for lang in Language.allCases {
            XCTAssertFalse(lang.flag.isEmpty, "\(lang) flag is empty")
        }
    }

    func testNativeNameIsNotEmpty() {
        for lang in Language.allCases {
            XCTAssertFalse(lang.nativeName.isEmpty, "\(lang) nativeName is empty")
        }
    }

    func testMeaningTitleIsNotEmpty() {
        for lang in Language.allCases {
            XCTAssertFalse(lang.meaningTitle.isEmpty, "\(lang) meaningTitle is empty")
        }
    }

    func testPromptInstructionIsNotEmpty() {
        for lang in Language.allCases {
            XCTAssertFalse(lang.promptInstruction.isEmpty, "\(lang) promptInstruction is empty")
        }
    }

    func testIdEqualsRawValue() {
        for lang in Language.allCases {
            XCTAssertEqual(lang.id, lang.rawValue)
        }
    }

    func testDefaults() {
        XCTAssertEqual(Language.defaultNative, .turkish)
        XCTAssertEqual(Language.defaultTarget, .english)
    }
}
