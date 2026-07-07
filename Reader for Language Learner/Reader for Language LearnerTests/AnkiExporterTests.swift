//
//  AnkiExporterTests.swift
//  Reader for Language LearnerTests
//

import XCTest
@testable import Reader_for_Language_Learner

final class AnkiExporterTests: XCTestCase {

    // MARK: - buildNote

    func testBuildNoteBasic() {
        let note = AnkiExporter.buildNote(
            selectedText: "hello",
            mode: .word,
            domain: .general,
            selectedModules: [.definitionEN],
            outputs: [.definitionEN: "a greeting"],
            includeSource: false,
            pdfFilename: nil,
            pageNumber: nil,
            tags: "vocab"
        )
        XCTAssertEqual(note.front, "hello")
        XCTAssertTrue(note.back.contains("a greeting"))
        XCTAssertEqual(note.tags, "vocab")
        XCTAssertEqual(note.source, "")
    }

    func testBuildNoteDomainBadge() {
        let note = AnkiExporter.buildNote(
            selectedText: "contract",
            mode: .word,
            domain: .legal,
            selectedModules: [],
            outputs: [:],
            includeSource: false,
            pdfFilename: nil,
            pageNumber: nil,
            tags: ""
        )
        XCTAssertTrue(note.front.contains("[Legal]"))
    }

    func testBuildNoteWithSource() {
        let note = AnkiExporter.buildNote(
            selectedText: "test",
            mode: .word,
            domain: .general,
            selectedModules: [],
            outputs: [:],
            includeSource: true,
            pdfFilename: "book.pdf",
            pageNumber: 42,
            tags: ""
        )
        XCTAssertEqual(note.source, "book.pdf (p. 42)")
    }

    func testBuildNoteContextSentence() {
        let note = AnkiExporter.buildNote(
            selectedText: "ephemeral",
            mode: .word,
            domain: .general,
            selectedModules: [.definitionEN],
            outputs: [.definitionEN: "lasting a short time"],
            includeSource: false,
            pdfFilename: nil,
            pageNumber: nil,
            contextSentence: "The ephemeral beauty of cherry blossoms.",
            tags: ""
        )
        XCTAssertTrue(note.back.contains("Context:"))
        XCTAssertTrue(note.back.contains("cherry blossoms"))
    }

    func testBuildNoteTagNormalization() {
        let note = AnkiExporter.buildNote(
            selectedText: "x",
            mode: .word,
            domain: .general,
            selectedModules: [],
            outputs: [:],
            includeSource: false,
            pdfFilename: nil,
            pageNumber: nil,
            tags: "  tag1   tag2  "
        )
        XCTAssertEqual(note.tags, "tag1 tag2")
    }

    // MARK: - TSV Serialization

    func testTsvRowFieldCount() {
        let note = AnkiNoteDraft(front: "a", back: "b", tags: "t", source: "s")
        let row = AnkiExporter.tsvRow(from: note)
        let fields = row.components(separatedBy: "\t")
        XCTAssertEqual(fields.count, 4)
        XCTAssertEqual(fields[0], "a")
        XCTAssertEqual(fields[1], "b")
    }

    func testTsvRowEscapesTabsAndNewlines() {
        let note = AnkiNoteDraft(front: "col1\tcol2", back: "line1\nline2", tags: "", source: "")
        let row = AnkiExporter.tsvRow(from: note)
        // Tabs in content should be replaced with spaces
        XCTAssertFalse(row.components(separatedBy: "\t")[0].contains("\t"))
        // Newlines should be replaced with <br>
        XCTAssertTrue(row.contains("<br>"))
    }

    func testTsvDocumentSingleNote() {
        let note = AnkiNoteDraft(front: "word", back: "def", tags: "tag", source: "src")
        let doc = AnkiExporter.tsvDocument(from: note)
        XCTAssertTrue(doc.hasPrefix("#separator:tab"))
        XCTAssertTrue(doc.contains("#html:true"))
        XCTAssertTrue(doc.contains("word"))
    }

    func testTsvDocumentMultipleNotes() {
        let notes = [
            AnkiNoteDraft(front: "a", back: "1", tags: "", source: ""),
            AnkiNoteDraft(front: "b", back: "2", tags: "", source: "")
        ]
        let doc = AnkiExporter.tsvDocument(from: notes)
        XCTAssertTrue(doc.contains("a\t1"))
        XCTAssertTrue(doc.contains("b\t2"))
    }

    func testTsvDocumentEmptyNotes() {
        let doc = AnkiExporter.tsvDocument(from: [])
        XCTAssertEqual(doc, "")
    }

    // MARK: - CSV Format

    func testCSVDocumentHasHeaderAndQuotesSpecialFields() {
        let notes = [
            AnkiNoteDraft(front: "run, ran", back: "<b>Context:</b> He said \"go\"<br>line two", tags: "verbs", source: "Book (p. 3)"),
        ]
        let doc = AnkiExporter.csvDocument(from: notes)
        let lines = doc.split(separator: "\n", omittingEmptySubsequences: false)

        XCTAssertEqual(lines[0], "Front,Back,Tags,Source")
        // Comma-bearing front must be quoted
        XCTAssertTrue(doc.contains("\"run, ran\""))
        // Inner quotes doubled per RFC 4180
        XCTAssertTrue(doc.contains("\"\"go\"\""))
        // HTML stripped from the back field
        XCTAssertFalse(doc.contains("<b>"))
        XCTAssertFalse(doc.contains("<br>"))
    }

    func testCSVDocumentEmptyNotes() {
        XCTAssertEqual(AnkiExporter.csvDocument(from: []), "")
    }

    // MARK: - Quizlet Format

    func testQuizletDocumentIsTwoColumnsWithoutHeaderOrMarkup() {
        let notes = [
            AnkiNoteDraft(front: "ephemeral", back: "<b>[Definition (EN)]</b><br>short-lived<br><br>more", tags: "ignored", source: "ignored"),
            AnkiNoteDraft(front: "lucid", back: "clear", tags: "", source: ""),
        ]
        let doc = AnkiExporter.quizletDocument(from: notes)
        let lines = doc.split(separator: "\n").map(String.init)

        XCTAssertEqual(lines.count, 2)
        XCTAssertFalse(lines[0].hasPrefix("#"), "Quizlet format must not carry the Anki header")

        let columns = lines[0].components(separatedBy: "\t")
        XCTAssertEqual(columns.count, 2, "exactly term<TAB>definition")
        XCTAssertEqual(columns[0], "ephemeral")
        XCTAssertFalse(columns[1].contains("<"), "HTML must be stripped")
        XCTAssertFalse(columns[1].contains("\n"), "definitions must be single-line")
        XCTAssertFalse(doc.contains("ignored"), "tags/source columns must not leak in")
    }

    func testPlainTextConversionStripsTagsAndKeepsLineBreaks() {
        let plain = AnkiExporter.plainText(fromAnkiHTML: "<b>Context:</b> hello<br><i>world</i>")
        XCTAssertEqual(plain, "Context: hello\nworld")
    }

    func testDocumentDispatchMatchesFormatSpecificBuilders() {
        let notes = [AnkiNoteDraft(front: "a", back: "b", tags: "t", source: "s")]
        XCTAssertEqual(AnkiExporter.document(from: notes, format: .ankiTSV), AnkiExporter.tsvDocument(from: notes))
        XCTAssertEqual(AnkiExporter.document(from: notes, format: .csv), AnkiExporter.csvDocument(from: notes))
        XCTAssertEqual(AnkiExporter.document(from: notes, format: .quizletTSV), AnkiExporter.quizletDocument(from: notes))
    }
}
