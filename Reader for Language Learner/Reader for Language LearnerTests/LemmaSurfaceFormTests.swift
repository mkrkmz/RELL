//
//  LemmaSurfaceFormTests.swift
//  Reader for Language LearnerTests
//
//  The reader-facing half of lemma matching (v10 Sprint 2, L-V1): given the
//  vocabulary's match keys, which words on this page are inflections of them.
//

import XCTest
@testable import Reader_for_Language_Learner

final class LemmaSurfaceFormTests: XCTestCase {

    /// Mirrors `SavedWordsStore.lemmaKeys(for:)`: a saved term contributes
    /// both its lemma and its literal form as keys.
    private func forms(_ text: String, _ terms: [String], _ language: Language = .english) -> [String] {
        var keys = Set(terms.map { LemmaMatcher.matchKey(for: $0, language: language) })
        keys.formUnion(terms.map { $0.lowercased() })
        return LemmaMatcher.surfaceForms(in: text, matchingKeys: keys, language: language)
            .map { $0.lowercased() }
    }

    func testFindsInflectionsOfASavedWord() {
        let found = forms("They ran home, and he is running still, so we run.", ["run"])
        XCTAssertTrue(found.contains("ran"), "got \(found)")
        XCTAssertTrue(found.contains("running"), "got \(found)")
        XCTAssertTrue(found.contains("run"), "got \(found)")
    }

    /// The whole point: the literal form is only one of the shapes.
    func testFindsTheSavedFormItself() {
        XCTAssertEqual(forms("A quiet orbit.", ["orbit"]), ["orbit"])
    }

    /// A word saved in an inflected form still matches the base form.
    func testSavedInflectionMatchesBaseForm() {
        let found = forms("The flat was empty.", ["flats"])
        XCTAssertTrue(found.contains("flat"), "got \(found)")
    }

    func testIgnoresWordsOutsideTheVocabulary() {
        let found = forms("They ran home.", ["orbit"])
        XCTAssertTrue(found.isEmpty, "got \(found)")
    }

    func testResultsAreDistinct() {
        let found = forms("run, run, run", ["run"])
        XCTAssertEqual(found, ["run"])
    }

    func testEmptyInputsProduceNothing() {
        XCTAssertTrue(LemmaMatcher.surfaceForms(in: "", matchingKeys: ["run"], language: .english).isEmpty)
        XCTAssertTrue(LemmaMatcher.surfaceForms(in: "they ran", matchingKeys: [], language: .english).isEmpty)
    }

    /// Surfaces come back as the text writes them — the highlighters match
    /// case-insensitively, but the string handed to them has to exist in the
    /// page for a range to be found at all.
    func testSurfaceCasingIsPreserved() {
        let raw = LemmaMatcher.surfaceForms(
            in: "Running is good.",
            matchingKeys: [LemmaMatcher.matchKey(for: "run", language: .english)],
            language: .english
        )
        XCTAssertEqual(raw, ["Running"])
    }

    /// NaturalLanguage's German lemmatizer is a downloadable asset, and a
    /// clean CI runner doesn't have it. Without it the tagger returns no lemma
    /// and the matcher falls back to exact matching — the documented contract,
    /// covered by the English cases above — so this asserts the extraction on
    /// top of a working tagger and skips where there isn't one.
    func testGermanInflectionIsFound() throws {
        let taggerKeys = LemmaMatcher.matchKeys(in: "Die Häuser stehen dort.", language: .german)
        try XCTSkipUnless(
            taggerKeys.contains("haus"),
            "German lemmatizer unavailable on this machine"
        )

        let found = forms("Die Häuser stehen dort.", ["Haus"], .german)
        XCTAssertTrue(found.contains("häuser"), "got \(found)")
    }
}
