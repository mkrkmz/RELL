//
//  PageAnalysisServiceTests.swift
//  Reader for Language LearnerTests
//
//  Only the pure candidate-extraction path is covered here — it has no
//  network dependency. The warming path itself calls QuickLookupService's
//  live LLM provider and is exercised manually (see plan doğrulama).
//

import XCTest
@testable import Reader_for_Language_Learner

final class PageAnalysisServiceTests: XCTestCase {

    func testCandidateWordsPicksContentWordsOnly() {
        let text = "The ephemeral butterfly quickly landed on a beautiful flower."
        let candidates = PageAnalysisService.candidateWords(from: text)

        // Content words (noun/verb/adjective, length >= 5) survive; short
        // function words ("The", "on", "a") never qualify by length alone.
        XCTAssertTrue(candidates.contains("ephemeral"))
        XCTAssertTrue(candidates.contains("butterfly"))
        XCTAssertTrue(candidates.contains("beautiful"))
        XCTAssertFalse(candidates.contains(where: { $0.count < 5 }))
    }

    func testCandidateWordsExcludesAlreadySavedTermsCaseInsensitively() {
        let text = "The ephemeral butterfly landed on a beautiful flower."
        let candidates = PageAnalysisService.candidateWords(from: text, excluding: ["Ephemeral", "FLOWER"])

        XCTAssertFalse(candidates.contains("ephemeral"))
        XCTAssertFalse(candidates.contains("flower"))
    }

    func testCandidateWordsDedupesRepeatedTerms() {
        let text = "Elephants remember elephants remember elephants."
        let candidates = PageAnalysisService.candidateWords(from: text)

        XCTAssertEqual(candidates.filter { $0.lowercased() == "elephants" }.count, 1)
    }

    func testCandidateWordsRespectsLimit() {
        let text = "Wonderful elephants gracefully remember beautiful gardens flourish endlessly forever."
        let candidates = PageAnalysisService.candidateWords(from: text, limit: 3)

        XCTAssertLessThanOrEqual(candidates.count, 3)
    }

    func testCandidateWordsEmptyForEmptyText() {
        XCTAssertTrue(PageAnalysisService.candidateWords(from: "").isEmpty)
    }
}
