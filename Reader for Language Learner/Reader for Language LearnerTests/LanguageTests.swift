//
//  LanguageTests.swift
//  Reader for Language LearnerTests
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class LanguageTests: XCTestCase {

    func testAllCasesCount() async {
        XCTAssertEqual(Language.allCases.count, 12)
    }

    func testRawValueRoundTrip() async {
        for lang in Language.allCases {
            XCTAssertEqual(Language(rawValue: lang.rawValue), lang)
        }
    }

    func testCodableRoundTrip() async throws {
        let original = Language.japanese
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Language.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testFlagIsNotEmpty() async {
        for lang in Language.allCases {
            XCTAssertFalse(lang.flag.isEmpty, "\(lang) flag is empty")
        }
    }

    func testNativeNameIsNotEmpty() async {
        for lang in Language.allCases {
            XCTAssertFalse(lang.nativeName.isEmpty, "\(lang) nativeName is empty")
        }
    }

    func testMeaningTitleIsNotEmpty() async {
        for lang in Language.allCases {
            XCTAssertFalse(lang.meaningTitle.isEmpty, "\(lang) meaningTitle is empty")
        }
    }

    func testPromptInstructionIsNotEmpty() async {
        for lang in Language.allCases {
            XCTAssertFalse(lang.promptInstruction.isEmpty, "\(lang) promptInstruction is empty")
        }
    }

    func testIdEqualsRawValue() async {
        for lang in Language.allCases {
            XCTAssertEqual(lang.id, lang.rawValue)
        }
    }

    func testDefaults() async {
        XCTAssertEqual(Language.defaultNative, .turkish)
        XCTAssertEqual(Language.defaultTarget, .english)
    }

    func testSpeechCodeIsValidBCP47ForEveryCase() async {
        let pattern = try! NSRegularExpression(pattern: "^[a-z]{2}-[A-Z]{2}$")
        for lang in Language.allCases {
            let code = lang.speechCode
            let range = NSRange(code.startIndex..., in: code)
            XCTAssertNotNil(
                pattern.firstMatch(in: code, range: range),
                "\(lang) speechCode \"\(code)\" isn't a valid xx-XX BCP-47 code"
            )
        }
    }

    func testSpeechCodesAreUnique() async {
        let codes = Language.allCases.map(\.speechCode)
        XCTAssertEqual(Set(codes).count, codes.count, "speechCode should uniquely identify each language")
    }

    func testUnknownWordIsNonEmptyForEveryCase() async {
        for lang in Language.allCases {
            XCTAssertFalse(lang.unknownWord.isEmpty, "\(lang) has no unknownWord fallback")
        }
        XCTAssertEqual(Language.turkish.unknownWord, "Bilinmiyor")
        XCTAssertEqual(Language.english.unknownWord, "Unknown")
    }

    func testShortCodesAreTwoLettersAndUnique() async {
        for lang in Language.allCases {
            XCTAssertEqual(lang.shortCode.count, 2, "\(lang) shortCode should be two letters")
            XCTAssertEqual(lang.shortCode, lang.shortCode.uppercased())
        }
        let codes = Language.allCases.map(\.shortCode)
        XCTAssertEqual(Set(codes).count, codes.count, "shortCode should uniquely identify each language")
    }
}
