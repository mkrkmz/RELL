//
//  PerformanceBaselineTests.swift
//  Reader for Language LearnerTests
//
//  Roadmap v14 Sprint 0: timings for the work behind opening and reading a
//  book, so the UI sprints can show they didn't make anything slower. They
//  measure, they don't assert — CI machines vary too much for a threshold;
//  the numbers are recorded in ROADMAP.md and compared by hand.
//
//  Fixtures are generated here (a 40-chapter EPUB, a 277-page PDF, a
//  1,000-word vocabulary), so no binary files live in the repository.
//

import AppKit
import PDFKit
import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class PerformanceBaselineTests: XCTestCase {

    // MARK: - Fixtures

    /// Deterministic prose: common words with rarer ones mixed in, ~25k
    /// characters per chapter — the size of a novel's chapter.
    private static func prose(paragraphs: Int, seed: Int) -> [String] {
        let common = ["the", "night", "was", "quiet", "and", "she", "walked", "slowly", "through", "old",
                      "streets", "while", "rain", "fell", "on", "roofs", "of", "town", "he", "thought",
                      "about", "letter", "his", "mother", "had", "written", "years", "ago", "they", "found"]
        let rare = ["landlady", "melancholy", "peculiar", "untimely", "drowsy", "inquisitive", "hideous",
                    "apprehension", "tenement", "squalor", "accustom", "elude", "decades", "pseudo"]
        var generator = SeededGenerator(seed: UInt64(seed))
        return (0..<paragraphs).map { _ in
            (0..<8).map { _ in
                let words = (0..<14).map { index -> String in
                    index % 7 == 3 ? rare.randomElement(using: &generator)! : common.randomElement(using: &generator)!
                }
                return words.joined(separator: " ").prefix(1).uppercased() + words.joined(separator: " ").dropFirst() + "."
            }.joined(separator: " ")
        }
    }

    private static let epub: Data = {
        let chapters = (0..<40).map { index in
            MiniEPUB.Chapter(
                title: "Chapter \(index + 1)",
                blocks: prose(paragraphs: 30, seed: index).map { .init(text: $0, isHeading: false) }
            )
        }
        return MiniEPUB.build(title: "Baseline", author: nil, language: "en", chapters: chapters)
    }()

    private static let pdfURL: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rell-baseline-277.pdf")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { return url }
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11)]
        for page in 0..<277 {
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            let text = prose(paragraphs: 3, seed: 1_000 + page).joined(separator: "\n\n")
            NSAttributedString(string: text, attributes: attributes)
                .draw(in: CGRect(x: 54, y: 54, width: 504, height: 684))
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }()

    private static let vocabulary: [SavedWord] = {
        let rare = ["landlady", "melancholy", "peculiar", "untimely", "drowsy", "inquisitive", "hideous",
                    "apprehension", "tenement", "squalor", "accustom", "elude", "decades", "pseudo"]
        return (0..<1_000).map { index in
            SavedWord(
                term: index < rare.count ? rare[index] : "term\(index)",
                sentence: "A sentence with term\(index) in it.",
                llmOutputs: [ModuleType.definitionEN.rawValue: String(repeating: "A definition. ", count: 20)],
                language: Language.english.rawValue
            )
        }
    }()

    private var options: XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        return options
    }

    // MARK: - Opening a book

    func testOpenAFortyChapterBookAndReadEveryChapter() async throws {
        let data = Self.epub
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            guard let book = try? EPUBDocument(archive: ZIPArchive(data: data)) else { return XCTFail("EPUB didn't open") }
            for chapter in 0..<book.chapterCount { _ = book.plainText(at: chapter) }
        }
    }

    func testOpenA277PagePDFAndReadTwentyPages() async throws {
        let url = Self.pdfURL
        measure(metrics: [XCTClockMetric()], options: options) {
            guard let document = PDFDocument(url: url) else { return XCTFail("PDF didn't open") }
            XCTAssertEqual(document.pageCount, 277)
            for index in stride(from: 0, to: 277, by: 14) { _ = document.page(at: index)?.string }
        }
    }

    // MARK: - Reading work done per page or chapter

    func testScanAChapterForAThousandSavedWords() async throws {
        let chapter = Self.prose(paragraphs: 30, seed: 7).joined(separator: "\n")
        let entries = Self.vocabulary.map { EncounterScanner.Entry(id: $0.id, term: $0.term) }
        measure(metrics: [XCTClockMetric()], options: options) {
            _ = EncounterScanner.scan(text: chapter, vocabulary: entries, language: .english)
        }
    }

    func testProfileAChapterAgainstTheVocabulary() async throws {
        let chapter = Self.prose(paragraphs: 30, seed: 8).joined(separator: "\n")
        let keys = Set(Self.vocabulary.prefix(500).map { $0.term })
        measure(metrics: [XCTClockMetric()], options: options) {
            _ = LexicalProfileBuilder.profile(text: chapter, language: .english, masteredKeys: keys, learningKeys: [])
        }
    }

    func testPickAChaptersWarmUpCandidates() async throws {
        let chapter = Self.prose(paragraphs: 30, seed: 9).joined(separator: "\n")
        measure(metrics: [XCTClockMetric()], options: options) {
            _ = ChapterWarmUp.candidates(in: chapter, language: .english, excludingKeys: [])
        }
    }

    // MARK: - Stores

    func testLoadAThousandSavedWords() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("saved_words.json")
        try JSONEncoder().encode(Self.vocabulary).write(to: url)
        var stores: [SavedWordsStore] = []
        measure(metrics: [XCTClockMetric()], options: options) {
            let store = SavedWordsStore(fileURL: url)
            XCTAssertEqual(store.words.count, 1_000)
            stores.append(store)
        }
    }

    // MARK: - Import

    func testExtractALongArticle() async throws {
        let body = Self.prose(paragraphs: 120, seed: 3).map { "<div><p>\($0)</p></div>" }.joined()
        let html = Data("<html><head><title>Long read</title></head><body><nav><p>Menu</p></nav><article>\(body)</article></body></html>".utf8)
        measure(metrics: [XCTClockMetric()], options: options) {
            _ = try? ArticleExtractor.extract(html: html)
        }
    }
}

/// SplitMix64 — reproducible fixtures without a dependency.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
