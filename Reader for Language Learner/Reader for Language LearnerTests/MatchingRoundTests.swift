//
//  MatchingRoundTests.swift
//  Reader for Language LearnerTests
//
//  The matching game's rules (v11 Sprint 2): who gets on the grid, what a tap
//  does, and when the round is over.
//

import XCTest
@testable import Reader_for_Language_Learner

final class MatchingRoundTests: XCTestCase {

    private func word(_ term: String, definition: String? = "a definition") -> SavedWord {
        SavedWord(
            term: term,
            llmOutputs: definition.map { [ModuleType.definitionEN.rawValue: $0] } ?? [:]
        )
    }

    private func round(_ words: [SavedWord]) -> MatchingRound? {
        MatchingRound(words: words, answer: { $0.usableDefinition })
    }

    private func makeWords(_ count: Int) -> [SavedWord] {
        (0..<count).map { word("term\($0)", definition: "definition \($0)") }
    }

    // MARK: - Building the grid

    func testRoundNeedsEnoughPairs() {
        XCTAssertNil(round(makeWords(MatchingRound.minimumPairs - 1)))
        XCTAssertNotNil(round(makeWords(MatchingRound.minimumPairs)))
    }

    /// A word with nothing to show opposite it can't be a pair — it drops out
    /// rather than putting a placeholder on the grid.
    func testWordsWithoutADefinitionAreLeftOut() throws {
        var words = makeWords(4)
        words.append(word("undefined", definition: nil))

        let round = try XCTUnwrap(self.round(words))
        XCTAssertEqual(round.pairCount, 4)
        XCTAssertFalse(round.terms.contains { $0.text == "undefined" })
    }

    /// Two cards reading the same word would make one pairing arbitrary and
    /// the other unwinnable.
    func testDuplicateTermsAreCollapsed() throws {
        var words = makeWords(4)
        words.append(word("TERM0", definition: "another definition"))

        let round = try XCTUnwrap(self.round(words))
        XCTAssertEqual(round.pairCount, 4)
    }

    func testEveryTermHasExactlyOneAnswer() throws {
        let round = try XCTUnwrap(self.round(makeWords(6)))
        XCTAssertEqual(Set(round.terms.map(\.wordID)), Set(round.answers.map(\.wordID)))
        XCTAssertEqual(round.terms.count, round.answers.count)
    }

    // MARK: - Playing

    func testMatchingAPairMarksItAndCountsNoMistake() throws {
        var round = try XCTUnwrap(self.round(makeWords(4)))
        let term = round.terms[0]
        let answer = try XCTUnwrap(round.answers.first { $0.wordID == term.wordID })

        XCTAssertEqual(round.selectTerm(term.id), .pending)
        XCTAssertEqual(round.selectAnswer(answer.id), .matched(term.wordID))
        XCTAssertTrue(round.isMatched(term))
        XCTAssertEqual(round.wrongAttempts, 0)
    }

    func testWrongPairCountsAMistakeAndClearsSelection() throws {
        var round = try XCTUnwrap(self.round(makeWords(4)))
        let term = round.terms[0]
        let wrongAnswer = try XCTUnwrap(round.answers.first { $0.wordID != term.wordID })

        _ = round.selectTerm(term.id)
        XCTAssertEqual(round.selectAnswer(wrongAnswer.id), .wrong)
        XCTAssertEqual(round.wrongAttempts, 1)
        XCTAssertNil(round.selectedTermID)
        XCTAssertNil(round.selectedAnswerID)
        XCTAssertFalse(round.isMatched(term))
    }

    /// Either column can be tapped first.
    func testAnswerFirstAlsoMatches() throws {
        var round = try XCTUnwrap(self.round(makeWords(4)))
        let answer = round.answers[0]
        let term = try XCTUnwrap(round.terms.first { $0.wordID == answer.wordID })

        XCTAssertEqual(round.selectAnswer(answer.id), .pending)
        XCTAssertEqual(round.selectTerm(term.id), .matched(answer.wordID))
    }

    func testTappingAMatchedCardDoesNothing() throws {
        var round = try XCTUnwrap(self.round(makeWords(4)))
        let term = round.terms[0]
        let answer = try XCTUnwrap(round.answers.first { $0.wordID == term.wordID })
        _ = round.selectTerm(term.id)
        _ = round.selectAnswer(answer.id)

        XCTAssertEqual(round.selectTerm(term.id), .pending)
        XCTAssertNil(round.selectedTermID)
        XCTAssertEqual(round.wrongAttempts, 0)
    }

    func testChangingYourMindReplacesTheSelection() throws {
        var round = try XCTUnwrap(self.round(makeWords(4)))
        _ = round.selectTerm(round.terms[0].id)
        XCTAssertEqual(round.selectTerm(round.terms[1].id), .pending)
        XCTAssertEqual(round.selectedTermID, round.terms[1].id)
        XCTAssertEqual(round.wrongAttempts, 0)
    }

    func testRoundCompletesWhenEveryPairIsMatched() throws {
        var round = try XCTUnwrap(self.round(makeWords(4)))
        XCTAssertFalse(round.isComplete)

        for term in round.terms {
            let answer = try XCTUnwrap(round.answers.first { $0.wordID == term.wordID })
            _ = round.selectTerm(term.id)
            _ = round.selectAnswer(answer.id)
        }
        XCTAssertTrue(round.isComplete)
        XCTAssertEqual(round.wrongAttempts, 0)
    }

    func testClearSelectionDropsAHalfMadePair() throws {
        var round = try XCTUnwrap(self.round(makeWords(4)))
        _ = round.selectTerm(round.terms[0].id)
        round.clearSelection()
        XCTAssertNil(round.selectedTermID)
    }
}
