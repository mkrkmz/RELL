//
//  MatchingRound.swift
//  Reader for Language Learner
//
//  One grid of the matching game (Roadmap v11 Sprint 2): a column of terms, a
//  column of their definitions, and the state of pairing them up.
//
//  Pure and free of view state so the rules — what makes a word eligible, what
//  counts as a wrong attempt, when the round is done — can be tested without
//  driving a grid of buttons.
//

import Foundation

struct MatchingRound: Equatable {

    /// One tappable cell. Its own `id` addresses the cell; `wordID` is what
    /// two cells have to agree on to be a match.
    struct Card: Identifiable, Equatable {
        let id: UUID
        let wordID: UUID
        let text: String
    }

    /// What a tap did. `pending` means the round is waiting for the other half
    /// of the pair.
    enum Outcome: Equatable {
        case pending
        case matched(UUID)
        case wrong
    }

    /// Below this a grid isn't a game — with three pairs the last one is free.
    static let minimumPairs = 4
    /// Comfortable grid on the review panel's width.
    static let defaultPairs = 5

    private(set) var terms: [Card]
    private(set) var answers: [Card]
    /// Word ids already paired up.
    private(set) var matchedWordIDs: Set<UUID> = []
    private(set) var wrongAttempts = 0
    private(set) var selectedTermID: UUID?
    private(set) var selectedAnswerID: UUID?

    /// Builds a round from the words that can actually be asked about.
    ///
    /// - Parameter answer: the text to show opposite the term — nil for a word
    ///   with no usable definition, which drops it from the round rather than
    ///   putting a placeholder on the grid.
    ///
    /// Returns nil when fewer than `minimumPairs` words qualify; the caller
    /// hides the mode rather than showing a grid that plays itself.
    init?(words: [SavedWord], answer: (SavedWord) -> String?) {
        var termCards: [Card] = []
        var answerCards: [Card] = []
        var seenTerms: Set<String> = []

        for word in words {
            guard let text = answer(word)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty
            else { continue }
            let term = word.term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { continue }
            // Two cards reading the same word would make one pairing arbitrary
            // and the other unwinnable.
            guard seenTerms.insert(term.lowercased()).inserted else { continue }

            termCards.append(Card(id: UUID(), wordID: word.id, text: term))
            answerCards.append(Card(id: UUID(), wordID: word.id, text: text))
        }

        guard termCards.count >= Self.minimumPairs else { return nil }
        // Shuffled apart, or the two columns would line up row by row.
        self.terms = termCards.shuffled()
        self.answers = answerCards.shuffled()
    }

    // MARK: - Derived

    var pairCount: Int { terms.count }
    var isComplete: Bool { matchedWordIDs.count == terms.count }

    func isMatched(_ card: Card) -> Bool { matchedWordIDs.contains(card.wordID) }

    // MARK: - Play

    /// Selects a term cell, resolving the pair when an answer is already
    /// chosen. Tapping a matched cell, or the selected one again, does nothing.
    mutating func selectTerm(_ id: UUID) -> Outcome {
        guard let card = terms.first(where: { $0.id == id }), !isMatched(card) else { return .pending }
        selectedTermID = id
        return resolve()
    }

    mutating func selectAnswer(_ id: UUID) -> Outcome {
        guard let card = answers.first(where: { $0.id == id }), !isMatched(card) else { return .pending }
        selectedAnswerID = id
        return resolve()
    }

    /// Clears a half-made selection (Esc, or tapping away).
    mutating func clearSelection() {
        selectedTermID = nil
        selectedAnswerID = nil
    }

    private mutating func resolve() -> Outcome {
        guard let termID = selectedTermID, let answerID = selectedAnswerID,
              let term = terms.first(where: { $0.id == termID }),
              let answer = answers.first(where: { $0.id == answerID })
        else { return .pending }

        clearSelection()

        guard term.wordID == answer.wordID else {
            wrongAttempts += 1
            return .wrong
        }
        matchedWordIDs.insert(term.wordID)
        return .matched(term.wordID)
    }
}
