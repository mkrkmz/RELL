//
//  SavedWordTests.swift
//  Reader for Language LearnerTests
//

import XCTest
@testable import Reader_for_Language_Learner

final class SavedWordTests: XCTestCase {

    func testCodableRoundTrip() throws {
        let word = SavedWord(
            term: "ubiquitous",
            sentence: "The technology is ubiquitous.",
            pdfFilename: "test.pdf",
            pageNumber: 42,
            mode: ExplainMode.word.rawValue,
            domain: DomainPreference.academic.rawValue,
            notes: "Common GRE word",
            llmOutputs: ["definitionEN": "Present everywhere."]
        )

        let data = try JSONEncoder().encode(word)
        let decoded = try JSONDecoder().decode(SavedWord.self, from: data)

        XCTAssertEqual(decoded.id, word.id)
        XCTAssertEqual(decoded.term, "ubiquitous")
        XCTAssertEqual(decoded.sentence, "The technology is ubiquitous.")
        XCTAssertEqual(decoded.pdfFilename, "test.pdf")
        XCTAssertEqual(decoded.pageNumber, 42)
        XCTAssertEqual(decoded.mode, ExplainMode.word.rawValue)
        XCTAssertEqual(decoded.domain, DomainPreference.academic.rawValue)
        XCTAssertEqual(decoded.notes, "Common GRE word")
        XCTAssertEqual(decoded.llmOutputs["definitionEN"], "Present everywhere.")
        XCTAssertEqual(decoded.reviewCount, 0)
        XCTAssertEqual(decoded.incorrectCount, 0)
        XCTAssertNil(decoded.lastReviewedAt)
        XCTAssertTrue(decoded.reviewHistory.isEmpty)
        XCTAssertNil(decoded.nextReviewAt)
    }

    func testDecodeLegacyWordDefaultsReviewHistory() throws {
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "term": "legacy"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(SavedWord.self, from: json)

        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.term, "legacy")
        XCTAssertTrue(decoded.reviewHistory.isEmpty)
        XCTAssertEqual(decoded.easeFactor, 2.5, "Words persisted before the ease-factor migration should default to the neutral ease")
        XCTAssertNil(decoded.cefrLevel)
        XCTAssertNil(decoded.language, "Pre-v1.24 words have no language key — SavedWordsStore backfills it at load time, not at decode time")
    }

    func testDefaultValues() {
        let word = SavedWord(term: "hello")
        XCTAssertEqual(word.sentence, "")
        XCTAssertNil(word.pdfFilename)
        XCTAssertNil(word.pageNumber)
        XCTAssertEqual(word.mode, ExplainMode.word.rawValue)
        XCTAssertEqual(word.domain, DomainPreference.general.rawValue)
        XCTAssertEqual(word.notes, "")
        XCTAssertTrue(word.llmOutputs.isEmpty)
        XCTAssertEqual(word.reviewCount, 0)
        XCTAssertEqual(word.incorrectCount, 0)
        XCTAssertTrue(word.reviewHistory.isEmpty)
        XCTAssertTrue(word.isDue())
        XCTAssertEqual(word.reviewStatus, .new)
        XCTAssertEqual(word.easeFactor, 2.5)
        XCTAssertNil(word.cefrLevel)
    }

    func testEquality() {
        let id = UUID()
        let date = Date()
        let a = SavedWord(id: id, term: "test", savedAt: date)
        let b = SavedWord(id: id, term: "test", savedAt: date)
        XCTAssertEqual(a, b)
    }

    func testInequalityDifferentID() {
        let a = SavedWord(term: "test")
        let b = SavedWord(term: "test")
        XCTAssertNotEqual(a, b, "Different UUIDs should produce inequality")
    }
}
