//
//  CEFREstimatorTests.swift
//  Reader for Language LearnerTests
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class CEFREstimatorTests: XCTestCase {
    private static var retainedStores: [SavedWordsStore] = []

    private func makeStore() -> SavedWordsStore {
        let store = SavedWordsStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("cefr_test_\(UUID().uuidString).json")
        )
        Self.retainedStores.append(store)
        return store
    }

    // MARK: - Strict single-token parse

    func testParseLevelAcceptsCleanTokens() {
        for level in CEFRLevel.allCases {
            XCTAssertEqual(CEFREstimator.parseLevel(level.rawValue), level)
        }
    }

    func testParseLevelToleratesWhitespaceCaseAndTrailingPunctuation() {
        XCTAssertEqual(CEFREstimator.parseLevel("  b2.\n"), .b2)
        XCTAssertEqual(CEFREstimator.parseLevel("C1!"), .c1)
    }

    func testParseLevelRejectsDriftedOutput() {
        XCTAssertNil(CEFREstimator.parseLevel("The level is B2"))
        XCTAssertNil(CEFREstimator.parseLevel("B2 or C1"))
        XCTAssertNil(CEFREstimator.parseLevel("D1"))
        XCTAssertNil(CEFREstimator.parseLevel(""))
    }

    // MARK: - Auto assignment never overwrites the user

    func testSetAutoCEFRLevelFillsUnratedWord() {
        let store = makeStore()
        let word = SavedWord(term: "orbit")
        store.add(word)

        store.setAutoCEFRLevel(.b1, forWordID: word.id)

        let updated = store.word(withID: word.id)
        XCTAssertEqual(updated?.cefrLevel, CEFRLevel.b1.rawValue)
        XCTAssertEqual(updated?.cefrIsAuto, true)
    }

    func testSetAutoCEFRLevelNeverOverwritesExistingLevel() {
        let store = makeStore()
        let word = SavedWord(term: "orbit", cefrLevel: CEFRLevel.c2.rawValue)
        store.add(word)

        store.setAutoCEFRLevel(.a1, forWordID: word.id)

        let updated = store.word(withID: word.id)
        XCTAssertEqual(updated?.cefrLevel, CEFRLevel.c2.rawValue)
        XCTAssertEqual(updated?.cefrIsAuto, false)
    }

    func testManualAssignmentClearsAutoFlag() {
        let store = makeStore()
        let word = SavedWord(term: "orbit")
        store.add(word)
        store.setAutoCEFRLevel(.b1, forWordID: word.id)

        store.setCEFRLevel(.b2, for: store.word(withID: word.id)!)

        let updated = store.word(withID: word.id)
        XCTAssertEqual(updated?.cefrLevel, CEFRLevel.b2.rawValue)
        XCTAssertEqual(updated?.cefrIsAuto, false)
    }

    // MARK: - Decode compatibility

    func testLegacyWordWithoutAutoFlagDecodesAsManual() throws {
        let legacyJSON = """
        {"id":"\(UUID().uuidString)","term":"orbit","cefrLevel":"B2"}
        """
        let decoded = try JSONDecoder().decode(SavedWord.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(decoded.cefrLevel, "B2")
        XCTAssertFalse(decoded.cefrIsAuto)
    }
}
