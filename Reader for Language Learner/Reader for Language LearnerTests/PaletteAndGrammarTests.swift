//
//  PaletteAndGrammarTests.swift
//  Reader for Language LearnerTests
//
//  v13 Sprint 5: how ⌘K ranks what you type, and the grammar lens's
//  part-of-speech tags.
//

import AppKit
import SwiftUI
import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class PaletteAndGrammarTests: XCTestCase {

    // MARK: - Palette ranking

    func testMatchQualityOrder() async throws {
        let exact = try XCTUnwrap(PaletteMatcher.score("zen mode", "Zen Mode"))
        let prefix = try XCTUnwrap(PaletteMatcher.score("zen", "Zen Mode"))
        let wordPrefix = try XCTUnwrap(PaletteMatcher.score("mode", "Zen Mode"))
        let substring = try XCTUnwrap(PaletteMatcher.score("en mo", "Zen Mode"))
        let letters = try XCTUnwrap(PaletteMatcher.score("zm", "Zen Mode"))
        XCTAssertGreaterThan(exact, prefix)
        XCTAssertGreaterThan(prefix, wordPrefix)
        XCTAssertGreaterThan(wordPrefix, substring)
        XCTAssertGreaterThan(substring, letters)
        XCTAssertNil(PaletteMatcher.score("xq", "Zen Mode"))
    }

    /// Turkish titles are typed without their accents more often than with.
    func testMatchingIgnoresCaseAndAccents() async {
        XCTAssertNotNil(PaletteMatcher.score("gunes", "Güneş Batarken"))
        XCTAssertNotNil(PaletteMatcher.score("ÇOK", "çok güzel"))
    }

    func testRankingPutsBetterMatchesAndCommandsFirst() async {
        struct Item { let title: String; let kind: Int }
        let items = [
            Item(title: "Sleep", kind: 3),                  // a saved word
            Item(title: "Why We Sleep", kind: 4),           // a book
            Item(title: "Sleep Timer", kind: 0),            // a command
        ]
        let ranked = PaletteMatcher.rank(items, query: "sleep", title: \.title, kind: \.kind)
        XCTAssertEqual(ranked.map(\.title), ["Sleep", "Sleep Timer", "Why We Sleep"])
        XCTAssertEqual(PaletteMatcher.rank(items, query: "", title: \.title, kind: \.kind).count, 3,
                       "an empty query lists everything in the given order")
    }

    func testPageNumberQueries() async {
        XCTAssertEqual(PaletteMatcher.pageNumber(in: "42"), 42)
        XCTAssertEqual(PaletteMatcher.pageNumber(in: "p 42"), 42)
        XCTAssertEqual(PaletteMatcher.pageNumber(in: "s.42".replacingOccurrences(of: ".", with: "")), 42)
        XCTAssertNil(PaletteMatcher.pageNumber(in: "zen"))
        XCTAssertNil(PaletteMatcher.pageNumber(in: "0"))
    }

    // MARK: - Grammar lens

    func testTagsPartsOfSpeech() async {
        let tokens = GrammarLens.tokens(in: "The old cat sleeps quietly.", language: .english)
        XCTAssertEqual(tokens.map(\.text), ["The", "old", "cat", "sleeps", "quietly"])
        XCTAssertEqual(tokens.map(\.kind), [.determiner, .adjective, .noun, .verb, .adverb])
    }

    /// The user saw simple-present sentences explained as past or
    /// continuous. The prompt now hands the model the verbs and asks for the
    /// tense from their form, in the reader's language.
    func testExplanationPromptIsGroundedInTheVerbs() async {
        let tokens = GrammarLens.tokens(in: "She drinks coffee every morning.", language: .english)
        let user = GrammarLens.userPrompt(sentence: "She drinks coffee every morning.", tokens: tokens)
        XCTAssertTrue(user.contains("Verb words the tagger found: drinks"), user)
        let system = GrammarLens.systemPrompt(target: .english, native: .turkish, level: .b1)
        XCTAssertTrue(system.contains("FORM"))
        XCTAssertTrue(system.contains("in Turkish"))
        XCTAssertTrue(system.contains("never from the time or meaning"))
    }

    func testLensIsForSentencesNotWordsOrPages() async {
        XCTAssertFalse(GrammarLens.isEligible("old cat"))
        XCTAssertTrue(GrammarLens.isEligible("The old cat sleeps."))
        XCTAssertFalse(GrammarLens.isEligible(String(repeating: "word ", count: 80)))
    }
}
