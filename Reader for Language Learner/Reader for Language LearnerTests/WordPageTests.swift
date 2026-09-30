//
//  WordPageTests.swift
//  Reader for Language LearnerTests
//
//  The word page's pure parts (v13 Sprint 1): recall right now, the reading
//  summary, where a jump lands, and which sentence a cloze card uses.
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class WordPageTests: XCTestCase {

    // MARK: - Recall

    func testRecallIsUnknownBeforeTheFirstReview() async {
        XCTAssertNil(WordPageModel.recallNow(SavedWord(term: "orbit")))
    }

    func testRecallFallsWithTime() async {
        let reviewed = Date(timeIntervalSince1970: 1_000_000)
        let word = SavedWord(term: "orbit", lastReviewedAt: reviewed, stability: 10, difficulty: 5)
        let soon = WordPageModel.recallNow(word, now: reviewed.addingTimeInterval(86_400))
        let later = WordPageModel.recallNow(word, now: reviewed.addingTimeInterval(30 * 86_400))
        XCTAssertNotNil(soon)
        XCTAssertGreaterThan(soon ?? 0, later ?? 1)
        XCTAssertEqual(WordPageModel.recallNow(word, now: reviewed) ?? 0, 1, accuracy: 0.0001)
    }

    // MARK: - Summary

    func testSummaryCountsOccurrencesAndDocuments() async {
        let id = UUID()
        let list = [
            encounter(id, path: "/a.pdf", occurrences: 3),
            encounter(id, path: "/a.pdf", location: 2, occurrences: 1),
            encounter(id, path: "/b.epub", occurrences: 2),
        ]
        let summary = WordPageModel.encounterSummary(list)
        XCTAssertNotNil(summary)
        XCTAssertTrue(summary?.contains("6") == true, summary ?? "")
        XCTAssertTrue(summary?.contains("2") == true, summary ?? "")
        XCTAssertNil(WordPageModel.encounterSummary([]))
    }

    /// Seen live: "Met 16 times in 1 documents".
    func testSummaryHasNoPluralForASingleDocument() async {
        let id = UUID()
        let one = WordPageModel.encounterSummary([encounter(id, occurrences: 16)]) ?? ""
        XCTAssertFalse(one.contains("1 documents"), one)
        XCTAssertTrue(one.contains("16"), one)
        let once = WordPageModel.encounterSummary([encounter(id, occurrences: 1)]) ?? ""
        XCTAssertFalse(once.contains("1 times"), once)
    }

    func testEmphasisMarksTheInflectedForm() async {
        let text = WordPageModel.emphasized("She ran for the train.", term: "run", language: .english)
        let bold = text.runs
            .filter { $0.inlinePresentationIntent == .stronglyEmphasized }
            .map { String(text[$0.range].characters) }
        XCTAssertEqual(bold, ["ran"])
    }

    // MARK: - Jump

    func testPreparedPDFJumpIsWhereTheDocumentOpens() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "WordPageTests-\(UUID())"))
        let url = URL(fileURLWithPath: "/tmp/Some Book.pdf")
        DocumentJump.prepare(DocumentLocation(url: url, location: 41, isEPUB: false), defaults: defaults)
        let model = ReaderWindowModel(defaults: defaults)
        XCTAssertEqual(model.savedPageIndex(for: "Some Book"), 41)
    }

    // MARK: - Cloze

    func testClozeRotatesThroughSavedAndMetSentences() async {
        let id = UUID()
        var word = SavedWord(id: id, term: "orbit", sentence: "Its orbit was slow.")
        let met = [
            encounter(id, sentence: "The orbit decayed.", date: Date(timeIntervalSince1970: 2)),
            encounter(id, sentence: "A new orbit began.", date: Date(timeIntervalSince1970: 1)),
        ]
        var seen: [String] = []
        for count in 0..<3 {
            word.reviewCount = count
            seen.append(ClozeContext.choice(for: word, encounters: met)?.masked ?? "")
        }
        XCTAssertEqual(Set(seen).count, 3, "\(seen)")
        XCTAssertFalse(seen.contains { $0.localizedCaseInsensitiveContains("orbit") }, "\(seen)")

        word.reviewCount = 0
        XCTAssertNil(ClozeContext.choice(for: word, encounters: met)?.source, "saved sentence first")
        word.reviewCount = 1
        XCTAssertEqual(ClozeContext.choice(for: word, encounters: met)?.source?.sentence, "A new orbit began.")
    }

    /// A sentence that only has an inflected form can't be graded against
    /// the saved term, so it's left out.
    func testClozeSkipsSentencesWithoutTheSavedForm() async {
        let id = UUID()
        let word = SavedWord(id: id, term: "run", sentence: "")
        XCTAssertNil(ClozeContext.choice(for: word, encounters: [encounter(id, sentence: "She ran home.")]))
    }

    func testClozeFallsBackToTheSavedSentenceAlone() async {
        let word = SavedWord(term: "orbit", sentence: "Its orbit was slow.")
        let choice = ClozeContext.choice(for: word, encounters: [])
        XCTAssertNotNil(choice)
        XCTAssertNil(choice?.source)
    }

    // MARK: - Helpers

    private func encounter(
        _ wordID: UUID,
        path: String = "/a.pdf",
        location: Int = 0,
        occurrences: Int = 1,
        sentence: String = "It was there.",
        date: Date = Date()
    ) -> WordEncounter {
        WordEncounter(
            wordID: wordID, documentPath: path, documentTitle: "A",
            location: location, isEPUB: path.hasSuffix(".epub"),
            sentence: sentence, occurrences: occurrences, date: date
        )
    }
}
