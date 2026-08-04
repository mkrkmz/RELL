//
//  HoverDictionaryLanguageTests.swift
//  Reader for Language LearnerTests
//
//  The hover dictionary's answer-language preference.
//

import XCTest
@testable import Reader_for_Language_Learner

final class HoverDictionaryLanguageTests: XCTestCase {

    private var previous: String?

    override func setUp() {
        super.setUp()
        previous = UserDefaults.standard.string(forKey: HoverDictionaryLanguage.storageKey)
    }

    override func tearDown() {
        UserDefaults.standard.set(previous, forKey: HoverDictionaryLanguage.storageKey)
        super.tearDown()
    }

    func testDefaultsToTheStudyLanguage() {
        UserDefaults.standard.removeObject(forKey: HoverDictionaryLanguage.storageKey)
        XCTAssertEqual(HoverDictionaryLanguage.stored, .target)
    }

    func testStoredValueRoundTrips() {
        UserDefaults.standard.set(HoverDictionaryLanguage.native.rawValue, forKey: HoverDictionaryLanguage.storageKey)
        XCTAssertEqual(HoverDictionaryLanguage.stored, .native)

        UserDefaults.standard.set(HoverDictionaryLanguage.target.rawValue, forKey: HoverDictionaryLanguage.storageKey)
        XCTAssertEqual(HoverDictionaryLanguage.stored, .target)
    }

    /// A value written by a future build (or a corrupted default) must fall
    /// back rather than leaving the reader with no hover dictionary at all.
    func testUnknownStoredValueFallsBackToTheDefault() {
        UserDefaults.standard.set("esperanto-only", forKey: HoverDictionaryLanguage.storageKey)
        XCTAssertEqual(HoverDictionaryLanguage.stored, HoverDictionaryLanguage.default)
    }

    func testTitlesNameTheActualLanguages() {
        let target = HoverDictionaryLanguage.target.localizedTitle(target: .german, native: .turkish)
        let native = HoverDictionaryLanguage.native.localizedTitle(target: .german, native: .turkish)

        XCTAssertTrue(target.contains(Language.german.nativeName), "the studying option should name the study language")
        XCTAssertTrue(native.contains(Language.turkish.nativeName), "the native option should name the native language")
        XCTAssertNotEqual(target, native)
    }

    func testBothChoicesAreOffered() {
        XCTAssertEqual(Set(HoverDictionaryLanguage.allCases.map(\.rawValue)), ["target", "native"])
    }
}
