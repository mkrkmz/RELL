//
//  SpotlightIndexerTests.swift
//  Reader for Language LearnerTests
//
//  Covers the pure identifier <-> target encoding used for Spotlight deep
//  links. Deliberately does not touch CSSearchableIndex.default() — that
//  talks to a real system service and isn't something a unit test should
//  depend on.
//

import XCTest
@testable import Reader_for_Language_Learner

final class SpotlightIndexerTests: XCTestCase {

    func testWordIdentifierRoundTrip() throws {
        let word = SavedWord(
            term: "ephemeral", sentence: "", pdfFilename: nil, pageNumber: nil,
            mode: "word", domain: "general", llmOutputs: [:]
        )
        let identifier = SpotlightIndexer.identifier(for: word)
        XCTAssertEqual(identifier, "word-\(word.id.uuidString)")

        let target = try XCTUnwrap(SpotlightIndexer.target(from: identifier))
        guard case .word(let id) = target else {
            return XCTFail("expected .word target, got \(target)")
        }
        XCTAssertEqual(id, word.id)
    }

    func testDocumentIdentifierRoundTrip() throws {
        let path = "/Users/test/Documents/Frankenstein.epub"
        let identifier = SpotlightIndexer.identifier(forDocumentPath: path)
        XCTAssertEqual(identifier, "doc-\(path)")

        let target = try XCTUnwrap(SpotlightIndexer.target(from: identifier))
        guard case .document(let url) = target else {
            return XCTFail("expected .document target, got \(target)")
        }
        XCTAssertEqual(url.path, path)
    }

    func testTargetFromUnknownPrefixReturnsNil() {
        XCTAssertNil(SpotlightIndexer.target(from: "something-else-123"))
        XCTAssertNil(SpotlightIndexer.target(from: ""))
    }

    func testTargetFromMalformedWordIdentifierReturnsNil() {
        // "word-" followed by a non-UUID string must fail cleanly rather
        // than crash — this is exactly what a corrupted or foreign
        // NSUserActivity payload would look like.
        XCTAssertNil(SpotlightIndexer.target(from: "word-not-a-uuid"))
    }

    func testTargetFromEmptyDocumentPathReturnsNil() {
        XCTAssertNil(SpotlightIndexer.target(from: "doc-"))
    }
}
