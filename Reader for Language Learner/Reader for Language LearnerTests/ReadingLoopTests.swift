//
//  ReadingLoopTests.swift
//  Reader for Language LearnerTests
//
//  The reading loop (v13 Sprint 2): when a recap is due and what it's
//  written from, which words a chapter warm-up offers, and how both read
//  the model's answer.
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class ReadingLoopTests: XCTestCase {

    // MARK: - Recap: when

    func testRecapIsDueAfterThreeDaysAway() async {
        let now = Date(timeIntervalSince1970: 10_000_000)
        let fourDays = now.addingTimeInterval(-4 * 86_400)
        let oneDay = now.addingTimeInterval(-86_400)
        XCTAssertTrue(ReadingRecap.isDue(lastOpenedAt: fourDays, now: now, hasProgress: true))
        XCTAssertFalse(ReadingRecap.isDue(lastOpenedAt: oneDay, now: now, hasProgress: true))
        XCTAssertEqual(ReadingRecap.daysAway(lastOpenedAt: fourDays, now: now, hasProgress: true), 4)
        XCTAssertNil(ReadingRecap.daysAway(lastOpenedAt: oneDay, now: now, hasProgress: true))
    }

    /// Nothing to recap in a book you haven't started.
    func testRecapIsNotDueWithoutProgress() async {
        let longAgo = Date().addingTimeInterval(-30 * 86_400)
        XCTAssertFalse(ReadingRecap.isDue(lastOpenedAt: longAgo, hasProgress: false))
        XCTAssertFalse(ReadingRecap.isDue(lastOpenedAt: nil, hasProgress: true))
    }

    // MARK: - Recap: what

    /// The recap may only see what was read — the spoiler rule.
    func testPassageStopsAtTheBookmark() async {
        let chapter = "Read part. " + "UNREAD PART."
        let passage = ReadingRecap.passage(current: chapter, upTo: 0.45)
        XCTAssertTrue(passage.contains("Read part"))
        XCTAssertFalse(passage.contains("UNREAD"))
    }

    func testPassageKeepsTheEndAndStartsOnAWord() async {
        let text = (0..<2_000).map { "word\($0)" }.joined(separator: " ")
        let passage = ReadingRecap.passage(current: text, limit: 100)
        XCTAssertLessThanOrEqual(passage.count, 100)
        XCTAssertTrue(passage.hasSuffix("word1999"))
        XCTAssertTrue(passage.hasPrefix("word"), passage)
    }

    func testPassageIncludesThePreviousChapterBeforeTheCurrent() async {
        let passage = ReadingRecap.passage(current: "Now.", upTo: 1, earlier: "Before.")
        XCTAssertEqual(passage, "Before.\n\nNow.")
    }

    // MARK: - Recap: answer

    /// Seen in the spike: the on-device model introduced itself first.
    func testCleanDropsPreambleAndListMarkers() async {
        let raw = """
        I am a foundation model developed by Apple.
        Here is a summary:
        - Raskolnikov walks away quickly.
        - **He** thinks about the girl.
        """
        XCTAssertEqual(
            ReadingRecap.clean(raw),
            "Raskolnikov walks away quickly. He thinks about the girl."
        )
        XCTAssertNil(ReadingRecap.clean("  \n "))
    }

    func testPromptsCarryLanguageAndLevel() async {
        let prompt = ReadingRecap.systemPrompt(language: .german, level: .a2)
        XCTAssertTrue(prompt.contains("German"))
        XCTAssertTrue(prompt.contains("A2"))
    }

    // MARK: - Warm-up: candidates

    func testCandidatesSkipShortWordsNamesAndSavedWords() async {
        let text = """
        Raskolnikov felt an overwhelming apprehension. The old woman was silent. \
        He could not accustom himself to the dreadful squalor of the tenement.
        """
        let candidates = ChapterWarmUp.candidates(in: text, language: .english, excludingKeys: ["squalor"])
        XCTAssertTrue(candidates.contains("apprehension"), "\(candidates)")
        XCTAssertTrue(candidates.contains("tenement"), "\(candidates)")
        XCTAssertFalse(candidates.contains("squalor"), "saved words aren't offered")
        XCTAssertFalse(candidates.contains { $0.contains("raskolnikov") }, "names aren't offered")
        XCTAssertFalse(candidates.contains("old"), "short words aren't offered")
        XCTAssertEqual(candidates, candidates.sorted(), "alphabetical — no frequency hint")
    }

    // MARK: - Warm-up: answer

    func testParseKeepsOnlyOfferedWordsInTheExpectedShape() async {
        let raw = """
        I am a foundation model developed by Apple, here to help.
        accustom | to get used to something
        **elude** | to escape from
        invented | a word that was never offered
        accustom | a repeat
        tenement: missing the bar
        """
        let words = ChapterWarmUp.parse(raw, offered: ["accustom", "elude", "tenement"])
        XCTAssertEqual(words.map(\.term), ["accustom", "elude"])
        XCTAssertEqual(words.first?.definition, "to get used to something")
    }

    func testParseStopsAtTheLimit() async {
        let offered = (0..<10).map { "word\($0)" }
        let raw = offered.map { "\($0) | meaning" }.joined(separator: "\n")
        XCTAssertEqual(ChapterWarmUp.parse(raw, offered: offered).count, ChapterWarmUp.maxWords)
    }

    func testSentencesAreAttachedFromTheChapter() async {
        let chapter = "It was late. They could not elude the watchman at the gate that night."
        let words = ChapterWarmUp.attachSentences(
            [.init(term: "elude", definition: "escape", sentence: "")],
            chapter: chapter,
            language: .english
        )
        XCTAssertEqual(words.first?.sentence, "They could not elude the watchman at the gate that night.")
    }

    // MARK: - Level

    func testLearnerLevelDefaultsToB1() async {
        XCTAssertEqual(CEFRLevel.defaultLearnerLevel, .b1)
    }
}
