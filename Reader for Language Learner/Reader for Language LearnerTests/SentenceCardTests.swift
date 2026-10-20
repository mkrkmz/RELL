//
//  SentenceCardTests.swift
//  Reader for Language LearnerTests
//
//  v19 Sprint 2 — saved sentences: what is saved as one, kept out of what
//  only words take part in, studied only on their own card, listed under
//  their own source, the words inside them, their translation and their
//  Anki card.
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class SentenceCardTests: XCTestCase {
    private let sentence = "She pulled her coat tighter and read the notice again."

    private func makeStore() -> SavedWordsStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rell-sentences-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return SavedWordsStore(fileURL: url)
    }

    private func sentenceCard(_ text: String? = nil, translation: String? = nil) -> SavedWord {
        SavedWord(term: text ?? sentence, mode: SavedWord.savedMode(for: text ?? sentence),
                  llmOutputs: translation.map { [SavedWord.translationKey: $0] } ?? [:],
                  language: Language.english.rawValue)
    }

    // MARK: What is a sentence

    func testFiveWordsOrMoreAreSavedAsASentence() {
        XCTAssertFalse(SavedWord.savesAsSentence("notice"))
        XCTAssertFalse(SavedWord.savesAsSentence("put up with"), "a phrasal verb is a word card")
        XCTAssertFalse(SavedWord.savesAsSentence("under the weather"))
        XCTAssertTrue(SavedWord.savesAsSentence("It's raining cats and dogs."))
        XCTAssertTrue(SavedWord.savesAsSentence(sentence))
        XCTAssertTrue(sentenceCard().isSentence)
        XCTAssertFalse(SavedWord(term: "put up with", mode: SavedWord.savedMode(for: "put up with")).isSentence)
    }

    func testATranslationIsReadBack() {
        XCTAssertEqual(sentenceCard(translation: "  Paltosuna sarıldı. ").translation, "Paltosuna sarıldı.")
        XCTAssertNil(sentenceCard(translation: "  ").translation)
    }

    // MARK: Kept out of word-only work

    func testSentencesStayOutOfWhatOnlyWordsTakePartIn() {
        let store = makeStore()
        store.add(SavedWord(term: "notice", language: Language.english.rawValue))
        store.add(sentenceCard())
        XCTAssertEqual(store.vocabulary.map(\.term), ["notice"])
        XCTAssertEqual(store.sentences.map(\.term), [sentence])
        XCTAssertEqual(store.terms(for: .english), ["notice"], "no underlining a whole sentence")
        XCTAssertFalse(store.lemmaKeys(for: .english).contains(sentence.lowercased()))
        let sets = store.lemmaKeySets(for: .english)
        XCTAssertFalse(sets.learning.union(sets.mastered).contains(where: { $0.contains(" ") }), "coverage counts words")
        XCTAssertNil(store.lemmaMatchedWord(for: sentence))
    }

    func testTheSameSentenceTwiceIsNotAWordSavedTwice() {
        let words = [sentenceCard(), sentenceCard()]
        XCTAssertTrue(WordMerge.duplicates(in: words, lemma: { term, _ in term }).isEmpty)
    }

    // MARK: Studied on its own card

    func testASentenceIsAskedOnlyOnItsOwnCard() {
        let card = sentenceCard()
        XCTAssertTrue(QuizMode.flashcard.asks(card))
        XCTAssertTrue(QuizMode.mixed.asks(card))
        for mode in [QuizMode.multipleChoice, .typed, .listening, .matching] {
            XCTAssertFalse(mode.asks(card), "\(mode.rawValue) can't ask a sentence")
            XCTAssertTrue(mode.asks(SavedWord(term: "notice")))
        }
        XCTAssertEqual(QuizMode.stageMode(for: card, canSpeak: true), .flashcard)
    }

    func testANewSentenceIsNotIntroducedLikeANewWord() {
        let session = QuizSession()
        session.introducesNewWords = true
        session.begin(with: [sentenceCard()], mode: .flashcard, shuffle: false)
        XCTAssertFalse(session.isIntroducing)
    }

    func testStudyingSentencesOnly() {
        let words = [SavedWord(term: "notice"), sentenceCard()]
        XCTAssertEqual(StudyPlan.words(in: .sentences, from: words).map(\.term), [sentence])
        XCTAssertEqual(StudyPlan.words(in: .all, from: words).count, 2, "a mixed session takes both")
    }

    // MARK: The notebook

    func testSentencesHaveTheirOwnSourceInTheNotebook() {
        var fromBook = sentenceCard()
        fromBook.pdfFilename = "Harbour Lights"
        let words = [SavedWord(term: "notice", pdfFilename: "Harbour Lights"), fromBook]
        XCTAssertEqual(WordNotebook.words(for: .sentences, from: words).map(\.term), [sentence])
        XCTAssertEqual(WordNotebook.words(for: .all, from: words).map(\.term), ["notice"])
        XCTAssertEqual(WordNotebook.words(for: .new, from: words).map(\.term), ["notice"])
        XCTAssertEqual(WordNotebook.words(for: .noBook, from: words).count, 0)
        XCTAssertEqual(WordNotebook.words(for: .deck("x"), from: words).count, 0)
    }

    func testTheWordsInsideASentence() {
        let store = makeStore()
        store.add(SavedWord(term: "notice", language: Language.english.rawValue))
        store.add(sentenceCard())
        XCTAssertEqual(SentenceWords.saved(in: sentence, store: store, language: .english).map(\.term), ["notice"])
        let candidates = SentenceWords.candidates(in: sentence, store: store, language: .english)
        XCTAssertTrue(candidates.contains("pulled"))
        XCTAssertTrue(candidates.contains("tighter"))
        XCTAssertFalse(candidates.contains("notice"), "already saved")
        XCTAssertFalse(candidates.contains("her"), "too short")
        XCTAssertFalse(candidates.contains("again"), "a common word")
    }

    // MARK: Translation

    func testASavedSentenceTakesTheStripsTranslation() async {
        let store = makeStore()
        let card = sentenceCard()
        store.add(card)
        let lookup = QuickLookupService()
        lookup.storeTranslation("Paltosuna daha sıkı sarıldı.", for: sentence)
        await SentenceTranslation.fill(wordID: card.id, store: store, quickLookup: lookup)
        XCTAssertEqual(store.word(withID: card.id)?.translation, "Paltosuna daha sıkı sarıldı.")
    }

    // MARK: Anki

    func testTheSentencesAnkiCard() {
        var card = sentenceCard(translation: "Paltosuna daha sıkı sarıldı.")
        card.notes = "From chapter 3."
        let note = AnkiExporter.buildSentenceNote(card, savedWords: [(term: "notice", meaning: "duyuru")],
                                                  includeSource: false, tags: "rell")
        XCTAssertEqual(note.front, sentence)
        XCTAssertTrue(note.back.contains("Paltosuna daha sıkı sarıldı."))
        XCTAssertTrue(note.back.contains("<b>notice</b> — duyuru"))
        XCTAssertTrue(note.back.contains("From chapter 3."))
    }
}
