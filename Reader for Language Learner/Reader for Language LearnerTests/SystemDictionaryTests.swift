//
//  SystemDictionaryTests.swift
//  Reader for Language LearnerTests
//
//  The system dictionary layer (v10 Sprint 4, L-E3). Which dictionaries are
//  enabled is the machine's business, so every case that needs a real entry
//  skips where there isn't one — what's asserted is the app's own rules
//  around the lookup, not Apple's dictionary contents.
//

import XCTest
@testable import Reader_for_Language_Learner

final class SystemDictionaryTests: XCTestCase {

    /// A word ordinary English dictionaries carry; also the probe for whether
    /// this machine has any active dictionary at all.
    private let probeWord = "sleep"

    func testEmptyTermIsNotLookedUp() {
        XCTAssertNil(SystemDictionary.rawDefinition(for: ""))
        XCTAssertNil(SystemDictionary.rawDefinition(for: "   "))
    }

    func testGibberishHasNoEntry() {
        XCTAssertNil(SystemDictionary.rawDefinition(for: "zzqqxyw"))
    }

    /// Sandbox check as much as anything: the app is sandboxed, and this is
    /// the layer silently doing nothing if Dictionary Services isn't reachable
    /// from inside it.
    func testLookupReachesTheSystemDictionaries() throws {
        let definition = SystemDictionary.rawDefinition(for: probeWord)
        try XCTSkipIf(definition == nil, "No active dictionary covers \"\(probeWord)\" on this machine")
        XCTAssertFalse(definition!.isEmpty)
    }

    /// The rule that keeps this layer from overriding the reader's "answer in"
    /// choice: an entry is only offered for the language it's written in. A
    /// bilingual dictionary can answer in either, so at most one of these two
    /// can be non-nil for the same word.
    func testEntryIsOfferedForAtMostOneLanguage() throws {
        try XCTSkipIf(
            SystemDictionary.rawDefinition(for: probeWord) == nil,
            "No active dictionary covers \"\(probeWord)\" on this machine"
        )

        let asEnglish = SystemDictionary.definition(for: probeWord, in: .english)
        let asTurkish = SystemDictionary.definition(for: probeWord, in: .turkish)

        XCTAssertFalse(
            asEnglish != nil && asTurkish != nil,
            "The same entry can't be both languages"
        )
    }

    /// A language nothing on this machine is likely to answer in must not be
    /// answered in anyway.
    func testMismatchedLanguageIsRejected() throws {
        try XCTSkipIf(
            SystemDictionary.rawDefinition(for: probeWord) == nil,
            "No active dictionary covers \"\(probeWord)\" on this machine"
        )
        XCTAssertNil(SystemDictionary.definition(for: probeWord, in: .korean))
    }

    func testEmptyTermHasNoLanguageMatchEither() {
        XCTAssertNil(SystemDictionary.definition(for: "", in: .english))
    }
}
