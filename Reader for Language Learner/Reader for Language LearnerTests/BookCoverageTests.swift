//
//  BookCoverageTests.swift
//  Reader for Language LearnerTests
//
//  Whole-book coverage (v10 Sprint 2, L-V2): the summing that lets the pass
//  run page by page, and the staleness rule that decides when to run it.
//

import XCTest
@testable import Reader_for_Language_Learner

final class BookCoverageTests: XCTestCase {

    // MARK: - Summing

    func testProfilesAddUp() {
        let first = LexicalProfile(totalTokens: 100, masteredTokens: 40, learningTokens: 10)
        let second = LexicalProfile(totalTokens: 50, masteredTokens: 5, learningTokens: 5)

        let sum = first.adding(second)

        XCTAssertEqual(sum.totalTokens, 150)
        XCTAssertEqual(sum.masteredTokens, 45)
        XCTAssertEqual(sum.learningTokens, 15)
        XCTAssertEqual(sum.unknownTokens, 90)
    }

    /// A book profiled page by page has to land where profiling it whole
    /// would — that equivalence is what makes the chunked pass legitimate.
    func testSummingPagesMatchesProfilingTheWholeText() {
        let pages = ["the cat sat on the mat", "the dog ran to the cat"]
        let mastered: Set<String> = ["cat"]
        let learning: Set<String> = ["dog"]

        let summed = pages
            .map { LexicalProfileBuilder.profile(text: $0, language: .english, masteredKeys: mastered, learningKeys: learning) }
            .reduce(LexicalProfile.empty) { $0.adding($1) }
        let whole = LexicalProfileBuilder.profile(
            text: pages.joined(separator: "\n"),
            language: .english,
            masteredKeys: mastered,
            learningKeys: learning
        )

        XCTAssertEqual(summed, whole)
    }

    func testAddingEmptyChangesNothing() {
        let profile = LexicalProfile(totalTokens: 10, masteredTokens: 2, learningTokens: 1)
        XCTAssertEqual(profile.adding(.empty), profile)
    }

    // MARK: - Staleness

    private func coverage(language: Language = .english, fingerprint: String = "3-abc") -> BookCoverage {
        BookCoverage(
            profile: LexicalProfile(totalTokens: 100, masteredTokens: 50, learningTokens: 20),
            language: language.rawValue,
            vocabularyFingerprint: fingerprint,
            computedAt: Date()
        )
    }

    func testSnapshotIsFreshForTheSameLanguageAndVocabulary() {
        XCTAssertTrue(coverage().isFresh(language: .english, fingerprint: "3-abc"))
    }

    func testSnapshotGoesStaleWhenVocabularyChanges() {
        XCTAssertFalse(coverage().isFresh(language: .english, fingerprint: "4-def"))
    }

    func testSnapshotGoesStaleWhenStudyLanguageChanges() {
        XCTAssertFalse(coverage().isFresh(language: .german, fingerprint: "3-abc"))
    }

    // MARK: - Persistence

    /// Every earlier snapshot of the library predates this field; decoding a
    /// whole array aborts on the first bad element, so a missing key has to
    /// decode to nil rather than throw.
    func testDocumentWithoutCoverageStillDecodes() throws {
        let json = """
        [{"id":"\(UUID().uuidString)","path":"/tmp/a.pdf","filename":"a","lastOpenedAt":0}]
        """
        let documents = try JSONDecoder().decode([RecentDocument].self, from: Data(json.utf8))

        XCTAssertEqual(documents.count, 1)
        XCTAssertNil(documents.first?.coverage)
    }

    func testCoverageSurvivesARoundTrip() throws {
        let document = RecentDocument(path: "/tmp/a.pdf", filename: "a", coverage: coverage())
        let data = try JSONEncoder().encode([document])
        let decoded = try JSONDecoder().decode([RecentDocument].self, from: data)

        XCTAssertEqual(decoded.first?.coverage, document.coverage)
    }
}
