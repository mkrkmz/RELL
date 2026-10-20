//
//  SpokenRepetitionTests.swift
//  Reader for Language LearnerTests
//
//  v19 Sprint 4 — repeating a sentence aloud: what was heard set against
//  the sentence word by word, what counts as the same word, what a saved
//  sentence keeps of it, and when the microphone shows at all.
//

import XCTest
@testable import Reader_for_Language_Learner
import Speech

@MainActor
final class SpokenRepetitionTests: XCTestCase {
    private let sentence = "She pulled her coat tighter and read the notice again."

    private func kinds(_ result: SpokenRepetition.Result) -> [String] {
        result.words.map { word in
            switch word.kind {
            case .said: return "✓"
            case .missed: return "–"
            case .different(let heard): return "≠\(heard)"
            }
        }
    }

    // MARK: Comparing

    func testEveryWordSaidIsSpotOnWhateverTheCaseAndPunctuation() {
        let result = SpokenRepetition.compare(sentence: sentence, heard: "she pulled her coat tighter and read the notice again")
        XCTAssertTrue(result.isPerfect)
        XCTAssertEqual(result.said, 10)
        XCTAssertEqual(result.words.last?.text, "again.", "shown as written")
        XCTAssertTrue(result.hardWords.isEmpty)
    }

    func testWordsHeardAsOthersAndWordsMissedAreTold() {
        let result = SpokenRepetition.compare(sentence: sentence, heard: "She pulled her coat tide and red the notice")
        XCTAssertEqual(kinds(result), ["✓", "✓", "✓", "✓", "≠tide", "✓", "≠red", "✓", "✓", "–"])
        XCTAssertEqual(result.said, 7)
        XCTAssertEqual(result.total, 10)
        XCTAssertEqual(result.hardWords, ["tighter", "read", "again"])
    }

    func testExtraWordsHeardAreNotCountedAgainstYou() {
        let result = SpokenRepetition.compare(sentence: "I saw the ferry leave.", heard: "um I saw the the ferry leave okay")
        XCTAssertTrue(result.isPerfect)
    }

    func testNothingHeardMeansEveryWordMissed() {
        let result = SpokenRepetition.compare(sentence: "I saw the ferry.", heard: "")
        XCTAssertEqual(kinds(result), ["–", "–", "–", "–"])
    }

    func testTheLastUnmatchedWordTakesWhatIsLeftOfWhatWasHeard() {
        let result = SpokenRepetition.compare(sentence: "She read the notice.", heard: "She read the no ties")
        XCTAssertEqual(kinds(result), ["✓", "✓", "✓", "≠no ties"])
    }

    func testANumberCountsHoweverItIsWritten() {
        XCTAssertTrue(SpokenRepetition.compare(sentence: "I sailed with her for eleven years.", heard: "I sailed with her for 11 years").isPerfect)
        XCTAssertTrue(SpokenRepetition.compare(sentence: "Üç kitap aldım.", heard: "3 kitap aldım").isPerfect)
    }

    func testOneLetterApartIsTheSameWordOnlyForLongerWords() {
        XCTAssertTrue(SpokenRepetition.matches("harbour", "harbor"))
        XCTAssertTrue(SpokenRepetition.matches("colour", "color"))
        XCTAssertFalse(SpokenRepetition.matches("read", "red"), "short words must match exactly")
        XCTAssertFalse(SpokenRepetition.matches("tighter", "tide"))
    }

    func testADashIsNothingToSay() {
        let result = SpokenRepetition.compare(sentence: "Wait — the ferry is late.", heard: "wait the ferry is late")
        XCTAssertTrue(result.isPerfect)
    }

    func testOnlyASentenceIsOffered() {
        XCTAssertFalse(SpokenRepetition.isEligible("notice"))
        XCTAssertFalse(SpokenRepetition.isEligible("put up"))
        XCTAssertTrue(SpokenRepetition.isEligible("put up with"))
    }

    // MARK: When the microphone shows

    func testTheMicrophoneShowsOnlyWhenItCanWork() {
        XCTAssertTrue(SpokenRepetition.offers(enabled: true, availability: .ready, access: .granted))
        XCTAssertTrue(SpokenRepetition.offers(enabled: true, availability: .ready, access: .notDetermined), "the first press explains, then asks")
        XCTAssertFalse(SpokenRepetition.offers(enabled: true, availability: .ready, access: .denied))
        XCTAssertFalse(SpokenRepetition.offers(enabled: true, availability: .noOnDeviceModel, access: .granted), "never off this Mac")
        XCTAssertFalse(SpokenRepetition.offers(enabled: true, availability: .unsupported, access: .granted))
        XCTAssertFalse(SpokenRepetition.offers(enabled: false, availability: .ready, access: .granted))
    }

    func testTheRightClickMenuOffersItAfterSpeak() {
        let entries = SelectionMenu.entries(includesNote: false, includesCopy: false, includesRepeat: true)
        XCTAssertEqual(entries.suffix(2), [.speak, .repeatAloud])
        XCTAssertFalse(SelectionMenu.entries(includesNote: false, includesCopy: false).contains(.repeatAloud))
    }

    // MARK: What a saved sentence keeps

    func testASavedSentenceKeepsCountsAndHardWordsOnly() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rell-repeat-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let store = SavedWordsStore(fileURL: url)
        let card = SavedWord(term: sentence, mode: ExplainMode.sentence.rawValue, language: Language.english.rawValue)
        let word = SavedWord(term: "notice", language: Language.english.rawValue)
        store.add(card)
        store.add(word)

        let result = SpokenRepetition.compare(sentence: sentence, heard: "She pulled her coat tide and red the notice")
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        store.recordSpokenRepetition(result, for: card.id, date: date)
        store.recordSpokenRepetition(result, for: word.id, date: date)

        let record = try XCTUnwrap(store.word(withID: card.id)?.spokenRepetition)
        XCTAssertEqual(record.said, 7)
        XCTAssertEqual(record.total, 10)
        XCTAssertEqual(record.hardWords, ["tighter", "read", "again"])
        XCTAssertEqual(record.date, date)
        let stored = try XCTUnwrap(store.word(withID: card.id)?.llmOutputs[SpokenRepetition.recordKey])
        XCTAssertFalse(stored.contains("tide"), "what was heard isn't kept")
        XCTAssertNil(store.word(withID: word.id)?.spokenRepetition, "only a saved sentence keeps a result")
        XCTAssertEqual(store.savedSentence(matching: "  " + sentence.uppercased())?.id, card.id)
        XCTAssertNil(store.savedSentence(matching: "notice"))
    }

    func testARecordKeepsAtMostEightHardWords() {
        let long = (1...12).map { "word\($0)" }.joined(separator: " ")
        let record = SpokenRepetition.Record(SpokenRepetition.compare(sentence: long, heard: ""))
        XCTAssertEqual(record.hardWords.count, 8)
        XCTAssertEqual(SpokenRepetition.Record.decoded(record.encoded), record)
        XCTAssertNil(SpokenRepetition.Record.decoded("not json"))
    }

    func testSpeechIsRecognisedOnThisMacOnly() {
        let request = SpokenRepetitionRecognizer.makeRequest()
        XCTAssertTrue(request.requiresOnDeviceRecognition)
        XCTAssertTrue(request.shouldReportPartialResults, "the words show as you speak")
    }
}
