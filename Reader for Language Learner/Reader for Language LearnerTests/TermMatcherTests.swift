//
//  TermMatcherTests.swift
//  Reader for Language LearnerTests
//

import XCTest
@testable import Reader_for_Language_Learner

final class TermMatcherTests: XCTestCase {

    private func ranges(_ term: String, _ text: String, limit: Int = .max) -> [NSRange] {
        TermMatcher.ranges(of: term, in: text as NSString, limit: limit)
    }

    // MARK: - Whole-word matching

    /// The v1.36 bug: a saved "run" underlined the middle of "brunt".
    func testDoesNotMatchInsideALongerWord() {
        XCTAssertTrue(ranges("run", "He bore the brunt of it.").isEmpty)
        XCTAssertTrue(ranges("run", "running").isEmpty)
        XCTAssertTrue(ranges("art", "start").isEmpty)
    }

    func testMatchesStandaloneWord() {
        let found = ranges("run", "They run every morning.")
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first, NSRange(location: 5, length: 3))
    }

    func testMatchesEveryOccurrence() {
        XCTAssertEqual(ranges("run", "run, run — RUN!").count, 3)
    }

    func testMatchingIsCaseInsensitive() {
        XCTAssertEqual(ranges("orbit", "Orbit and ORBIT").count, 2)
    }

    func testPunctuationAndLineBreaksAreBoundaries() {
        XCTAssertEqual(ranges("run", "(run)").count, 1)
        XCTAssertEqual(ranges("run", "run\nfast").count, 1)
        XCTAssertEqual(ranges("run", "\"run\"").count, 1)
    }

    /// A hyphen is not a letter or digit, so each side is its own word — the
    /// same call the EPUB regex makes.
    func testHyphenIsABoundary() {
        XCTAssertEqual(ranges("run", "run-down").count, 1)
    }

    func testDigitsAreNotBoundaries() {
        XCTAssertTrue(ranges("run", "run2").isEmpty)
        XCTAssertTrue(ranges("run", "2run").isEmpty)
    }

    // MARK: - Non-ASCII scripts

    func testAccentedLatinBoundaries() {
        XCTAssertEqual(ranges("café", "the café closed").count, 1)
        // "cafés" is a different word — the trailing letter blocks the match.
        XCTAssertTrue(ranges("café", "two cafés").isEmpty)
        // A combining accent directly after the match is part of the word.
        XCTAssertTrue(ranges("cafe", "cafe\u{0301}").isEmpty)
    }

    func testCyrillicAndGermanBoundaries() {
        XCTAssertEqual(ranges("слово", "одно слово тут").count, 1)
        XCTAssertTrue(ranges("слово", "словом").isEmpty)
        XCTAssertEqual(ranges("Straße", "die Straße hier").count, 1)
    }

    /// CJK has no whitespace segmentation, so these keep substring matching —
    /// a boundary rule would reject every real match.
    func testCJKUsesSubstringMatching() {
        XCTAssertFalse(TermMatcher.usesWholeWordMatching("勉強"))
        XCTAssertFalse(TermMatcher.usesWholeWordMatching("こと"))
        XCTAssertFalse(TermMatcher.usesWholeWordMatching("사람"))
        XCTAssertEqual(ranges("勉強", "毎日勉強します").count, 1)
        XCTAssertEqual(ranges("사람", "그 사람은").count, 1)
    }

    func testLatinTermsUseWholeWordMatching() {
        XCTAssertTrue(TermMatcher.usesWholeWordMatching("run"))
        XCTAssertTrue(TermMatcher.usesWholeWordMatching("Straße"))
        XCTAssertTrue(TermMatcher.usesWholeWordMatching("слово"))
    }

    /// Surrogate pairs must be recombined before the boundary test, or the
    /// scan reads half a character.
    func testSurrogatePairNeighbourIsNotAWordCharacter() {
        XCTAssertEqual(ranges("run", "🏃run🏃").count, 1)
    }

    // MARK: - Phrases and edges

    func testMultiWordTermMatchesAsAPhrase() {
        XCTAssertEqual(ranges("give up", "don't give up now").count, 1)
        XCTAssertTrue(ranges("give up", "give upon it").isEmpty)
    }

    func testTermIsTrimmedAndEmptyTermMatchesNothing() {
        XCTAssertEqual(ranges("  run  ", "they run").count, 1)
        XCTAssertTrue(ranges("   ", "they run").isEmpty)
        XCTAssertTrue(ranges("run", "").isEmpty)
    }

    func testLimitCapsResults() {
        XCTAssertEqual(ranges("run", "run run run run", limit: 2).count, 2)
        XCTAssertTrue(ranges("run", "run run", limit: 0).isEmpty)
    }

    /// Rejected matches must not stall the scan.
    func testRejectedMatchDoesNotBlockLaterMatches() {
        let found = ranges("run", "brunt, then run")
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.location, 12)
    }
}
