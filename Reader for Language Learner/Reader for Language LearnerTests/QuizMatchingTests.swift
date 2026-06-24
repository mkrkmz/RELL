//
//  QuizMatchingTests.swift
//  Reader for Language LearnerTests
//

import XCTest
@testable import Reader_for_Language_Learner

final class QuizMatchingTests: XCTestCase {

    // MARK: - Normalization

    func testNormalizeStripsCaseDiacriticsPunctuation() {
        XCTAssertEqual(QuizMatching.normalized("  Yörüngé,  bir!! "), "yorunge bir")
    }

    // MARK: - Typed matching

    func testLooksCorrectSubstring() {
        XCTAssertTrue(QuizMatching.looksCorrect(typed: "circular path", definition: "A circular path around a body."))
    }

    func testLooksCorrectTokenOverlap() {
        XCTAssertTrue(QuizMatching.looksCorrect(typed: "orbiting around", definition: "Movement around a planet."))
    }

    func testLooksWrongWhenNoOverlap() {
        XCTAssertFalse(QuizMatching.looksCorrect(typed: "banana", definition: "A circular path around a body."))
    }

    func testLooksWrongForTrivialInput() {
        XCTAssertFalse(QuizMatching.looksCorrect(typed: "a", definition: "Anything at all."))
    }

    // MARK: - Distractors

    func testDistractorsExcludeCorrectAndDuplicates() {
        let result = QuizMatching.distractors(
            correct: "to assume",
            candidates: ["to assume", "TO ASSUME", "a planet", "a planet", "a star"]
        )
        XCTAssertEqual(result, ["a planet", "a star"])
    }

    func testDistractorsSkipEmptyAndPlaceholder() {
        let result = QuizMatching.distractors(
            correct: "right",
            candidates: ["", "No definition saved.", "left", "up"]
        )
        XCTAssertEqual(result, ["left", "up"])
    }

    func testDistractorsRespectLimit() {
        let result = QuizMatching.distractors(
            correct: "x",
            candidates: ["a", "b", "c", "d", "e"],
            limit: 3
        )
        XCTAssertEqual(result, ["a", "b", "c"])
    }
}
