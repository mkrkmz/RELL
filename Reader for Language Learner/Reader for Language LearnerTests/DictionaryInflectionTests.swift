//
//  DictionaryInflectionTests.swift
//  Reader for Language LearnerTests
//
//  1.48 live pass: the Inspector card showed a bilingual dictionary entry's
//  grammar and inflections ("transitive verb past -camepast participle
//  -comeyenmek…") instead of the meaning. Entries as this Mac returned them.
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class DictionaryInflectionTests: XCTestCase {
    private let overcome = "overcome transitive verb past -camepast participle -comeyenmek; galip gelmek ▸ be overcome by (insanı) zayıf düşürmek "
    private let take = "take | teik | transitive verb past tookpast participle taken1 almak; kazanmak 2 with one yanında götürmek 3 take to a place alıp götürmek "
    private let sleepVerb = "sleep | sliːp | intransitive verb past participle, past sleptuyumak "

    private let english: Set<String> = ["took", "taken", "slept", "with", "one", "take", "place"]
    private func isEnglish(_ word: String) -> Bool { english.contains(word.lowercased()) }

    func testGluedInflectionsBeforeTheMeaningGo() throws {
        XCTAssertEqual(try XCTUnwrap(DictionaryEntry(raw: overcome)).senses(isEnglishWord: isEnglish), ["yenmek", "galip gelmek"],
                       "a hyphenated form is the headword's tail")
        XCTAssertEqual(try XCTUnwrap(DictionaryEntry(raw: take)).senses(isEnglishWord: isEnglish).first, "almak; kazanmak",
                       "a form glued to the sense number")
        XCTAssertEqual(try XCTUnwrap(DictionaryEntry(raw: sleepVerb)).senses(isEnglishWord: isEnglish), ["uyumak"],
                       "a form glued to the meaning ends at the longest English word")
    }

    func testAnEntryWithoutInflectionsIsUntouched() {
        XCTAssertEqual(DictionaryEntry.droppingInflections("rıhtım; iskele", headword: "quay", isEnglishWord: isEnglish), "rıhtım; iskele")
        XCTAssertEqual(DictionaryEntry.droppingInflections("past xqzwrt", headword: "quay", isEnglishWord: { _ in false }), "past xqzwrt",
                       "a form whose end can't be found leaves the text as it was")
    }

    func testTheCardShowsTheShortMeaningFromTheDictionary() {
        let meaning = WordFillEngine.dictionaryAnswer(for: "overcome", raw: overcome, native: .turkish, target: .english,
                                                      isTargetWord: isEnglish)[.meaning]
        XCTAssertEqual(meaning, "yenmek; galip gelmek")
    }
}
