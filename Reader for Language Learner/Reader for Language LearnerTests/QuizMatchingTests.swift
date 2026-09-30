//
//  QuizMatchingTests.swift
//  Reader for Language LearnerTests
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class QuizMatchingTests: XCTestCase {

    // MARK: - Normalization

    func testNormalizeStripsCaseDiacriticsPunctuation() async {
        XCTAssertEqual(QuizMatching.normalized("  Yörüngé,  bir!! "), "yorunge bir")
    }

    // MARK: - Typed term matching (objective)

    func testMatchesTermExact() async {
        XCTAssertTrue(QuizMatching.matchesTerm(typed: "circumstance", term: "circumstance"))
    }

    func testMatchesTermIgnoresCaseWhitespacePunctuation() async {
        XCTAssertTrue(QuizMatching.matchesTerm(typed: "  Give Up! ", term: "give up"))
    }

    func testMatchesTermIgnoresDiacritics() async {
        XCTAssertTrue(QuizMatching.matchesTerm(typed: "yorunge", term: "Yörüngé"))
    }

    func testMatchesTermRejectsDifferentWord() async {
        XCTAssertFalse(QuizMatching.matchesTerm(typed: "circumstances are", term: "circumstance"))
        XCTAssertFalse(QuizMatching.matchesTerm(typed: "banana", term: "circumstance"))
    }

    func testMatchesTermRejectsEmptyInput() async {
        XCTAssertFalse(QuizMatching.matchesTerm(typed: "   ", term: "coma"))
    }

    // MARK: - Term masking

    func testMaskTermMasksStartMiddleEndOccurrences() async {
        let masked = QuizMatching.maskTerm(
            "coma",
            in: "Coma is rare; a deep coma may end in coma"
        )
        XCTAssertEqual(masked, "••• is rare; a deep ••• may end in •••")
    }

    func testMaskTermMasksQuotedForm() async {
        let masked = QuizMatching.maskTerm(
            "coma",
            in: "In this context, \"coma\" refers to unconsciousness."
        )
        XCTAssertEqual(masked, "In this context, \"•••\" refers to unconsciousness.")
    }

    func testMaskTermIsCaseAndDiacriticInsensitive() async {
        XCTAssertEqual(
            QuizMatching.maskTerm("yörünge", in: "Yorunge kavramı önemlidir."),
            "••• kavramı önemlidir."
        )
    }

    func testMaskTermDoesNotMaskInsideLongerWords() async {
        // "cat" must not mask "category" (5 extra letters — beyond inflection).
        XCTAssertEqual(
            QuizMatching.maskTerm("cat", in: "The category of a cat."),
            "The category of a •••."
        )
    }

    func testMaskTermMasksSimpleSuffixInflections() async {
        XCTAssertEqual(
            QuizMatching.maskTerm("circumstance", in: "Those circumstances changed."),
            "Those ••• changed."
        )
    }

    func testMaskTermMasksYToIeInflection() async {
        XCTAssertEqual(
            QuizMatching.maskTerm("fatality", in: "Traffic fatalities increased."),
            "Traffic ••• increased."
        )
    }

    func testMaskTermMasksMultiWordTerm() async {
        XCTAssertEqual(
            QuizMatching.maskTerm("give up", in: "Don't give up on sleep."),
            "Don't ••• on sleep."
        )
    }

    func testMaskTermLeavesTextWithoutOccurrences() async {
        let text = "Nothing to hide here."
        XCTAssertEqual(QuizMatching.maskTerm("coma", in: text), text)
    }

    // MARK: - Distractors

    func testDistractorsExcludeCorrectAndDuplicates() async {
        let result = QuizMatching.distractors(
            correct: "to assume",
            candidates: ["to assume", "TO ASSUME", "a planet", "a planet", "a star"]
        )
        XCTAssertEqual(result, ["a planet", "a star"])
    }

    func testDistractorsSkipEmptyAndPlaceholder() async {
        let result = QuizMatching.distractors(
            correct: "right",
            candidates: ["", "No definition saved.", "left", "up"]
        )
        XCTAssertEqual(result, ["left", "up"])
    }

    func testDistractorsRespectLimit() async {
        let result = QuizMatching.distractors(
            correct: "x",
            candidates: ["a", "b", "c", "d", "e"],
            limit: 3
        )
        XCTAssertEqual(result, ["a", "b", "c"])
    }
}
