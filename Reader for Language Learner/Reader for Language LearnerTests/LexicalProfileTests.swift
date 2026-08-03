//
//  LexicalProfileTests.swift
//  Reader for Language LearnerTests
//
//  Lemma matching (L2) and document coverage (L3), Roadmap v9 Sprint 3.
//
//  NaturalLanguage's lemmatizer is a system component whose coverage varies by
//  language and OS version, so these assert the *contract* — exact matches
//  always hold, lemma matching only ever adds hits, shares stay coherent —
//  rather than pinning specific lemmas the system might not always produce.
//

import XCTest
@testable import Reader_for_Language_Learner

final class LexicalProfileTests: XCTestCase {

    // MARK: - LemmaMatcher

    func testExactMatchesAlwaysHold() {
        XCTAssertTrue(LemmaMatcher.matches("run", "run", language: .english))
        XCTAssertTrue(LemmaMatcher.matches("Run", "run", language: .english), "matching is case-insensitive")
        XCTAssertTrue(LemmaMatcher.matches(" run ", "run", language: .english), "surrounding space is trimmed")
    }

    func testUnrelatedWordsDoNotMatch() {
        XCTAssertFalse(LemmaMatcher.matches("run", "elephant", language: .english))
        XCTAssertFalse(LemmaMatcher.matches("house", "car", language: .german))
    }

    func testEmptyInputNeverMatches() {
        XCTAssertFalse(LemmaMatcher.matches("", "run", language: .english))
        XCTAssertFalse(LemmaMatcher.matches("run", "   ", language: .english))
    }

    /// The lemma of an inflected form must not be some unrelated word — if the
    /// tagger returns anything, it should relate the two surface forms or fall
    /// back to the exact form.
    func testMatchKeyFallsBackToTheTermItself() {
        // A nonsense token has no lemma, so its key is the normalized term.
        let key = LemmaMatcher.matchKey(for: "zzqqxx", language: .english)
        XCTAssertEqual(key, "zzqqxx")
    }

    func testMatchKeyIsLowercasedAndTrimmed() {
        XCTAssertEqual(LemmaMatcher.matchKey(for: "  ZZQQXX  ", language: .english), "zzqqxx")
    }

    func testMultiWordPhrasesFallBackToExactComparison() {
        XCTAssertTrue(LemmaMatcher.matches("New York", "new york", language: .english))
        XCTAssertFalse(LemmaMatcher.matches("New York", "Old York", language: .english))
    }

    func testMatchKeysCoversEveryWordInText() {
        let keys = LemmaMatcher.matchKeys(in: "The cat sat on the mat.", language: .english)
        XCTAssertEqual(keys.count, 6, "six words, punctuation omitted")
        XCTAssertTrue(keys.allSatisfy { !$0.isEmpty })
        XCTAssertTrue(keys.allSatisfy { $0 == $0.lowercased() })
    }

    func testMatchKeysOnEmptyTextIsEmpty() {
        XCTAssertTrue(LemmaMatcher.matchKeys(in: "", language: .english).isEmpty)
    }

    // MARK: - LexicalProfile shares

    func testSharesSplitTheDocument() {
        let profile = LexicalProfile(totalTokens: 100, masteredTokens: 60, learningTokens: 20)
        XCTAssertEqual(profile.unknownTokens, 20)
        XCTAssertEqual(profile.masteredShare, 0.6, accuracy: 0.0001)
        XCTAssertEqual(profile.knownShare, 0.8, accuracy: 0.0001)
        XCTAssertEqual(profile.unknownShare, 0.2, accuracy: 0.0001)
    }

    func testEmptyProfileIsAllZeroNotDivideByZero() {
        let profile = LexicalProfile.empty
        XCTAssertEqual(profile.knownShare, 0)
        XCTAssertEqual(profile.unknownShare, 0)
        XCTAssertEqual(profile.unknownTokens, 0)
    }

    func testDifficultyBandsFollowComprehensibleInputThresholds() {
        let comfortable = LexicalProfile(totalTokens: 100, masteredTokens: 96, learningTokens: 0)
        let challenging = LexicalProfile(totalTokens: 100, masteredTokens: 85, learningTokens: 0)
        let demanding   = LexicalProfile(totalTokens: 100, masteredTokens: 50, learningTokens: 0)
        XCTAssertEqual(comfortable.difficulty, .comfortable)
        XCTAssertEqual(challenging.difficulty, .challenging)
        XCTAssertEqual(demanding.difficulty, .demanding)
    }

    func testLearningWordsCountTowardKnownButNotMastered() {
        let profile = LexicalProfile(totalTokens: 100, masteredTokens: 40, learningTokens: 55)
        XCTAssertEqual(profile.difficulty, .comfortable, "95% is followable even if not all mastered")
        XCTAssertEqual(profile.masteredShare, 0.4, accuracy: 0.0001)
    }

    // MARK: - Profile building

    func testProfileCountsMasteredAndLearningTokens() {
        let text = "the cat sat on the mat"
        let mastered: Set<String> = ["the"]
        let learning: Set<String> = ["cat"]

        let profile = LexicalProfileBuilder.profile(
            text: text, language: .english,
            masteredKeys: mastered, learningKeys: learning
        )

        XCTAssertEqual(profile.totalTokens, 6)
        XCTAssertEqual(profile.masteredTokens, 2, "'the' appears twice")
        XCTAssertEqual(profile.learningTokens, 1)
        XCTAssertEqual(profile.unknownTokens, 3)
    }

    func testProfileWithNoSavedWordsIsAllUnknown() {
        let profile = LexicalProfileBuilder.profile(
            text: "alpha beta gamma", language: .english,
            masteredKeys: [], learningKeys: []
        )
        XCTAssertEqual(profile.totalTokens, 3)
        XCTAssertEqual(profile.unknownTokens, 3)
        XCTAssertEqual(profile.knownShare, 0, accuracy: 0.0001)
        XCTAssertEqual(profile.difficulty, .demanding)
    }

    func testProfileOfEmptyTextIsEmpty() {
        let profile = LexicalProfileBuilder.profile(
            text: "   ", language: .english,
            masteredKeys: ["x"], learningKeys: []
        )
        XCTAssertEqual(profile, .empty)
    }

    func testTokenCountsNeverExceedTotal() {
        let profile = LexicalProfileBuilder.profile(
            text: "the the the", language: .english,
            masteredKeys: ["the"], learningKeys: ["the"]
        )
        XCTAssertEqual(profile.masteredTokens + profile.learningTokens, profile.totalTokens)
        XCTAssertEqual(profile.learningTokens, 0, "mastered takes precedence over learning")
    }
}
