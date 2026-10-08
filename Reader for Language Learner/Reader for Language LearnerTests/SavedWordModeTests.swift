//
//  SavedWordModeTests.swift
//  Reader for Language LearnerTests
//
//  v15 S0: four save paths stored the explain mode as "word" while the rest
//  of the app reads "Word" (21 of the user's 59 words). Stored modes are
//  normalised when read and when a word is made.
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class SavedWordModeTests: XCTestCase {

    func testLowercaseStoredModeReadsAsTheRawValue() async throws {
        let id = UUID()
        let json = #"[{"id":"\#(id.uuidString)","term":"peculiar","mode":"word"},{"id":"\#(UUID().uuidString)","term":"in debt","mode":"SENTENCE"}]"#
        let words = try JSONDecoder().decode([SavedWord].self, from: Data(json.utf8))
        XCTAssertEqual(words.map(\.mode), [ExplainMode.word.rawValue, ExplainMode.sentence.rawValue])
        XCTAssertEqual(ExplainMode(rawValue: words[0].mode), .word)
    }

    func testNewWordsNormaliseTheirMode() async {
        XCTAssertEqual(SavedWord(term: "landlady", sentence: "", mode: "word").mode, ExplainMode.word.rawValue)
        XCTAssertEqual(ExplainMode.normalizedRawValue("unknown"), "unknown", "an unknown value is kept, not guessed")
    }
}
