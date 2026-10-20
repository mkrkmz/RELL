//
//  WritingAndComprehensionTests.swift
//  Reader for Language LearnerTests
//
//  v19 Sprint 3 — writing a sentence with a word, and the comprehension
//  check: how the model's labelled replies are read, which verdict stands,
//  which quote may be shown, which pages a PDF check covers, what's
//  remembered of past checks, and that neither touches the schedule.
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class WritingAndComprehensionTests: XCTestCase {

    // MARK: Labelled replies

    func testALabelledReplyIsReadThroughBoldAndListMarks() {
        let raw = """
        Sure! Here you go.
        **VERDICT:** FIXED
        - CORRECTED: The notice on the door says
        that the shop is closed.
        WHY: Fiil -s alır.
        """
        let parts = LabelledReply.sections(raw, labels: ["VERDICT:", "CORRECTED:", "WHY:"])
        XCTAssertEqual(parts["VERDICT:"], "FIXED")
        XCTAssertEqual(parts["CORRECTED:"], "The notice on the door says\nthat the shop is closed.")
        XCTAssertEqual(parts["WHY:"], "Fiil -s alır.")
    }

    // MARK: Writing a sentence

    private let written = "The notice on the door say that the shop is close"

    private func reply(verdict: String, corrected: String, topic: String = "özne-fiil uyumu") -> String {
        """
        VERDICT: \(verdict)
        CORRECTED: "\(corrected)"
        WHY: Tekil özneden sonra fiil -s alır.
        EXAMPLE: A notice at the station warned that all trains were delayed.
        TOPIC: \(topic)
        """
    }

    func testAnEditedSentenceCountsAsFixedWhateverTheModelCalledIt() throws {
        let feedback = try XCTUnwrap(SentenceWriting.parse(
            reply(verdict: "NATURAL", corrected: "The notice on the door says that the shop is closed."), written: written))
        XCTAssertEqual(feedback.verdict, .fixed)
        XCTAssertEqual(feedback.corrected, "The notice on the door says that the shop is closed.", "quotes stripped")
        XCTAssertEqual(feedback.example, "A notice at the station warned that all trains were delayed.")
        XCTAssertEqual(feedback.topic, "özne-fiil uyumu")
    }

    func testAnUntouchedSentenceIsNaturalAndHasNoFix() throws {
        let feedback = try XCTUnwrap(SentenceWriting.parse(reply(verdict: "FIXED", corrected: written), written: written))
        XCTAssertEqual(feedback.verdict, .natural)
        XCTAssertNil(feedback.topic, "nothing was fixed")
    }

    func testAWordInAnotherSenseSaysSo() throws {
        let feedback = try XCTUnwrap(SentenceWriting.parse(
            reply(verdict: "OTHER SENSE", corrected: "I didn't notice the sign."), written: "I didn't notice the sign."))
        XCTAssertEqual(feedback.verdict, .otherSense)
        XCTAssertEqual(try XCTUnwrap(SentenceWriting.parse(
            reply(verdict: "OTHER_SENSE", corrected: written), written: written)).verdict, .otherSense)
    }

    func testAReplyWithoutACorrectionOrAReasonIsNotShown() {
        XCTAssertNil(SentenceWriting.parse("VERDICT: NATURAL\nWHY: Güzel.", written: written))
        XCTAssertNil(SentenceWriting.parse("VERDICT: NATURAL\nCORRECTED: \(written)", written: written))
        XCTAssertNil(SentenceWriting.parse("Looks good to me!", written: written))
    }

    func testTheNoneTopicIsNoTopic() throws {
        let feedback = try XCTUnwrap(SentenceWriting.parse(
            reply(verdict: "FIXED", corrected: "The notice says so.", topic: "NONE"), written: "The notice say so."))
        XCTAssertNil(feedback.topic)
    }

    func testTheCommonestFixNeedsToComeUpTwice() {
        func fixed(_ topic: String?) -> SentenceWriting.Feedback {
            SentenceWriting.Feedback(verdict: .fixed, corrected: "x", why: "y", example: "", topic: topic)
        }
        XCTAssertNil(SentenceWriting.commonestTopic([fixed("a"), fixed("b")]))
        let common = SentenceWriting.commonestTopic([fixed("Özne-fiil uyumu"), fixed("özne-fiil uyumu"), fixed("b"), fixed(nil)])
        XCTAssertEqual(common?.count, 2)
    }

    func testThePromptCarriesTheSenseAndTheBookSentenceWhenThereAreSome() {
        let full = SentenceWriting.userPrompt(word: "notice", sense: "duyuru", bookSentence: "She read the notice.", sentence: "A notice.")
        XCTAssertTrue(full.contains("SENSE: duyuru"))
        XCTAssertTrue(full.contains("WHERE THE LEARNER MET IT: She read the notice."))
        let bare = SentenceWriting.userPrompt(word: "notice", sense: nil, bookSentence: "", sentence: "A notice.")
        XCTAssertFalse(bare.contains("SENSE"))
        XCTAssertFalse(bare.contains("WHERE"))
        XCTAssertFalse(SentenceWriting.isWorthChecking("A notice"))
        XCTAssertTrue(SentenceWriting.isWorthChecking("I saw a notice"))
    }

    // MARK: Writing in the study room

    func testWritingIsPracticeAndNeverAsksASentence() {
        XCTAssertFalse(QuizMode.write.affectsSchedule)
        XCTAssertTrue(QuizMode.write.isRoomOnly)
        XCTAssertFalse(QuizMode.write.isRoundBased)
        XCTAssertFalse(QuizMode.write.asks(SavedWord(term: "She pulled her coat tighter.", mode: ExplainMode.sentence.rawValue)))
        XCTAssertTrue(QuizMode.write.asks(SavedWord(term: "notice")))
    }

    func testAWritingRunLeavesTheScheduleAlone() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rell-writing-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let store = SavedWordsStore(fileURL: url)
        let words = [SavedWord(term: "notice"), SavedWord(term: "harbour")]
        words.forEach { store.add($0) }
        let session = QuizSession()
        session.cram = true
        session.begin(with: words, mode: .write, shuffle: false)
        session.recordWriting(SentenceWriting.Feedback(verdict: .natural, corrected: "x", why: "y", example: "", topic: nil))
        session.noteWritingSaved()
        session.advanceWriting()
        XCTAssertEqual(session.currentWord?.term, "harbour")
        session.advanceWriting()
        XCTAssertTrue(session.isFinished)
        XCTAssertEqual(session.writings.count, 1)
        XCTAssertEqual(session.savedWritings, 1)
        XCTAssertTrue(session.answers.isEmpty)
        for word in words {
            XCTAssertEqual(store.word(withID: word.id)?.reviewCount, 0)
            XCTAssertNil(store.word(withID: word.id)?.nextReviewAt)
        }
        session.begin(with: words, mode: .write, shuffle: false)
        XCTAssertTrue(session.writings.isEmpty, "a new run starts clean")
        XCTAssertEqual(session.savedWritings, 0)
    }

    func testAWordsPageListsTheSentencesItIsIn() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rell-writing-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let store = SavedWordsStore(fileURL: url)
        let notice = SavedWord(term: "notice", language: Language.english.rawValue)
        store.add(notice)
        store.add(SavedWord(term: "The notice on the door says that the shop is closed.",
                            mode: ExplainMode.sentence.rawValue, language: Language.english.rawValue))
        store.add(SavedWord(term: "The ferry turned its lights toward the sea.",
                            mode: ExplainMode.sentence.rawValue, language: Language.english.rawValue))
        XCTAssertEqual(SentenceWords.sentences(containing: notice, store: store).map(\.term),
                       ["The notice on the door says that the shop is closed."])
    }

    func testBothWaitOnTheQueueLikeAnythingYouAskedFor() {
        for origin in [LLMRequestOrigin.writing, .comprehension] {
            XCTAssertEqual(origin.priority, .interactive)
            XCTAssertTrue(origin.isForeground)
        }
    }

    // MARK: Comprehension questions

    func testQuestionsAreReadInTheirUsualShapes() {
        let raw = """
        Here are your questions:
        **Q1 [MAIN]:** Why did Mara go to the harbour?
        Q2 (DETAIL) - What did the notice say?
        Q3. Why do you think the old man helped her?
        """
        let questions = ComprehensionCheck.parseQuestions(raw)
        XCTAssertEqual(questions.map(\.text), ["Why did Mara go to the harbour?", "What did the notice say?",
                                               "Why do you think the old man helped her?"])
        XCTAssertEqual(questions.map(\.kind), [.mainIdea, .detail, .why])
        XCTAssertEqual(questions.map(\.id), [1, 2, 3])
    }

    func testOneQuestionIsNotACheck() {
        XCTAssertTrue(ComprehensionCheck.parseQuestions("Q1 [MAIN]: Why did she go?").isEmpty)
        XCTAssertTrue(ComprehensionCheck.parseQuestions("I can't write questions about this.").isEmpty)
    }

    // MARK: Grading

    private let passage = """
    The rain had stopped by the time Mara reached the harbour. She pulled her coat tighter and read the \
    notice again. “All crossings suspended until further notice.” An old man by the rail said, \
    “I sailed with your mother for eleven years.”
    """

    func testGradesAreReadPerAnswerAndABlankAnswerIsSkippedNotMissed() throws {
        let raw = """
        ANSWER 1
        VERDICT: UNDERSTOOD
        CORRECTED: She wanted to take the ferry home.
        NOTE: Doğru.
        QUOTE: She pulled her coat tighter and read the notice again.

        **ANSWER 2:**
        VERDICT: PARTLY
        CORRECTED: NONE
        NOTE: Bir şey eksik: yeni bir duyuruya kadar.
        QUOTE: "All crossings suspended until further notice."
        """
        let answers = [1: "She wanted to take the ferry to home.", 2: "All crossings were suspended.", 3: "  "]
        let grades = ComprehensionCheck.parseGrades(raw, answers: answers, passage: passage)
        let first = try XCTUnwrap(grades[1])
        XCTAssertEqual(first.verdict, .understood)
        XCTAssertEqual(first.corrected, "She wanted to take the ferry home.")
        XCTAssertEqual(first.quote, "She pulled her coat tighter and read the notice again.")
        let second = try XCTUnwrap(grades[2])
        XCTAssertEqual(second.verdict, .partly)
        XCTAssertNil(second.corrected, "NONE is no correction")
        XCTAssertEqual(second.quote, "All crossings suspended until further notice.", "curly quotes in the book match straight ones")
        XCTAssertEqual(grades[3]?.verdict, .skipped)
        XCTAssertEqual(ComprehensionCheck.score(grades.filter { $0.value.verdict != .skipped }).understood, 1)
    }

    func testAQuoteTheBookDoesntContainIsNeverShown() {
        XCTAssertNil(ComprehensionCheck.verifiedQuote("Mara was afraid of the sea all her life.", in: passage))
        XCTAssertNil(ComprehensionCheck.verifiedQuote("read the notice", in: passage), "too short to point at")
        XCTAssertNotNil(ComprehensionCheck.verifiedQuote("“I SAILED with your   mother for eleven years.”", in: passage))
    }

    func testACorrectionThatChangesNothingIsNoCorrection() throws {
        let raw = "ANSWER 1\nVERDICT: MISSED\nCORRECTED: He knew her mother.\nNOTE: Adam onu tanıyordu."
        let grade = try XCTUnwrap(ComprehensionCheck.parseGrades(raw, answers: [1: "He knew her mother."], passage: passage)[1])
        XCTAssertEqual(grade.verdict, .missed)
        XCTAssertNil(grade.corrected)
        XCTAssertNil(grade.quote)
    }

    // MARK: What a check covers

    func testAPDFCheckRunsFromTheSessionsStartToThePageOnScreen() {
        XCTAssertEqual(ComprehensionCheck.pdfRange(sessionStart: 40, current: 46), 40...46)
        XCTAssertEqual(ComprehensionCheck.pdfRange(sessionStart: nil, current: 46), 46...46)
        XCTAssertEqual(ComprehensionCheck.pdfRange(sessionStart: 10, current: 46), 35...46, "twelve pages at most")
        XCTAssertEqual(ComprehensionCheck.pdfRange(sessionStart: 60, current: 46), 46...46, "never ahead of the reader")
    }

    func testOnlyAChapterLongEnoughIsOfferedACheck() {
        XCTAssertFalse(ComprehensionCheck.isLongEnough(passage))
        XCTAssertTrue(ComprehensionCheck.isLongEnough(String(repeating: "word ", count: ComprehensionCheck.minimumWords)))
    }

    func testAChapterPassageStopsWhereTheReaderIs() {
        let chapter = "First half of the chapter. " + "Second half, not yet read."
        let passage = ComprehensionCheck.chapterPassage(chapter, readUpTo: 0.5)
        XCTAssertTrue(passage.hasPrefix("First half"))
        XCTAssertFalse(passage.contains("not yet read"))
    }

    // MARK: History

    func testTheLastCheckIsKeptAndAnOfferIsAskedOnce() throws {
        let suite = "rell-comprehension-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let key = ComprehensionHistory.key(book: "/books/harbour.epub", chapter: 2)
        XCTAssertEqual(key, "/books/harbour.epub#c2")
        XCTAssertEqual(ComprehensionHistory.key(book: "/books/a.pdf", chapter: nil), "/books/a.pdf#pdf")

        ComprehensionHistory.markOffered(key, defaults: defaults)
        XCTAssertNotNil(ComprehensionHistory.entry(for: key, defaults: defaults), "offered: not asked again")
        XCTAssertNil(ComprehensionHistory.lastCheck(for: key, defaults: defaults), "an offer isn't a check")

        ComprehensionHistory.record(2, of: 3, for: key, defaults: defaults)
        ComprehensionHistory.markOffered(key, defaults: defaults)
        let last = try XCTUnwrap(ComprehensionHistory.lastCheck(for: key, defaults: defaults))
        XCTAssertEqual(last.understood, 2)
        XCTAssertEqual(last.total, 3)
    }

    func testHistoryKeepsTheNewestOnly() throws {
        let suite = "rell-comprehension-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for index in 0...ComprehensionHistory.capacity {
            ComprehensionHistory.record(1, of: 3, for: "book#c\(index)", now: start.addingTimeInterval(Double(index)), defaults: defaults)
        }
        XCTAssertNil(ComprehensionHistory.entry(for: "book#c0", defaults: defaults), "the oldest goes")
        XCTAssertNotNil(ComprehensionHistory.entry(for: "book#c\(ComprehensionHistory.capacity)", defaults: defaults))
    }
}
