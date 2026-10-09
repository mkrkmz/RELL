//
//  BookIdentityTests.swift
//  Reader for Language LearnerTests
//
//  v16 Sprint 0 — the same book under its many names. The names are the
//  user's own (Kindle titles, downloaded files, an EPUB's title); measured on
//  their 590 words, title matching found 8 pairs, all right, none wrong.
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class BookIdentityTests: XCTestCase {

    private let kindle = "Why We Sleep"
    private let pdf = "Matthew Walker PhD - Why We Sleep_ Unlocking the Power of Sleep and Dreams-Scribner (2017)"
    private let epub = "Why We Sleep_ Unlocking the Power of Sleep and Dreams -- Walker, Matthew -- 2215bbe2fa1ffc1b477714adb7464da8 -- Anna’s Archive"
    private let epubTitle = "Why We Sleep: Unlocking the Power of Sleep and Dreams"

    func testOneBookUnderFourNames() async {
        let names = [kindle, pdf, epub, epubTitle]
        for a in names { for b in names {
            XCTAssertTrue(BookIdentity.sameBook(a, b), "\(a) / \(b)")
        } }
        XCTAssertTrue(BookIdentity.sameBook(
            "Harry Potter and The Chamber of Secrets",
            "Harry Potter and the Chamber of Secrets -- J_ K_ Rowling -- 1999 -- Scholastic -- isbn13 9780738301426 -- 8922d19e85444bbb7b0adfb7153dc0fa -- Anna’s Archive (1)"))
        XCTAssertTrue(BookIdentity.sameBook(
            "I went looking for surveillance cameras in my neighbourhood: I found so many more than I thought",
            "i-went-looking-for-surveillance-cameras-in-my-neighbourhood-"))
    }

    func testDifferentBooksStayApart() async {
        XCTAssertFalse(BookIdentity.sameBook("The Hunger Games - Suzanne Collins", "Suzanne Collins - Catching Fire"))
        XCTAssertFalse(BookIdentity.sameBook("BBC News", "Champions League_ Can Manchester City get revenge in Real Madrid semi-final rematch_ - BBC Sport"))
        XCTAssertFalse(BookIdentity.sameBook("science.aeg0769", "science.aeg0770"))
        XCTAssertFalse(BookIdentity.sameBook("Sleep", "Why We Sleep"), "one word matches only itself")
        let story = String(repeating: "The landlady found the flats in a strange state. Why We Sleep. ", count: 4)
        XCTAssertFalse(BookIdentity.sameBook(kindle, story), "a whole story isn't a title")
    }

    func testAWordBelongsToItsFileFirstThenItsBooksNames() async {
        let document = BookIdentity.Document(path: "/Books/\(pdf).pdf", names: [pdf, epubTitle])
        let fromKindle = SavedWord(term: "slumber", pdfFilename: kindle)
        let fromThisFile = SavedWord(term: "drowsy", pdfFilename: "renamed", documentPath: "/Books/\(pdf).pdf")
        let fromElsewhere = SavedWord(term: "manure", pdfFilename: "Harry Potter and The Chamber of Secrets")

        XCTAssertTrue(BookIdentity.isSaved(fromKindle, in: document))
        XCTAssertFalse(BookIdentity.isSaved(fromKindle, in: document, matchingTitles: false), "the per-book switch")
        XCTAssertTrue(BookIdentity.isSaved(fromThisFile, in: document), "the file, whatever its name")
        XCTAssertFalse(BookIdentity.isSaved(fromElsewhere, in: document))
    }

    func testOldFilesOpenWithoutTheNewField() async throws {
        let old = #"[{"id":"\#(UUID().uuidString)","term":"landlady","pdfFilename":"Crime and Punishment"}]"#
        let word = try XCTUnwrap(try JSONDecoder().decode([SavedWord].self, from: Data(old.utf8)).first)
        XCTAssertNil(word.documentPath)
        let saved = SavedWord(term: "x", documentPath: "/a.epub")
        XCTAssertEqual(try JSONDecoder().decode(SavedWord.self, from: JSONEncoder().encode(saved)).documentPath, "/a.epub")
    }
}
