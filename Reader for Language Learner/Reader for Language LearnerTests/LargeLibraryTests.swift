//
//  LargeLibraryTests.swift
//  Reader for Language LearnerTests
//
//  Roadmap v19 Sprint 0: how the work behind the notebook, the study room
//  and reading scales to a large library — 5,000 saved words and a
//  1,000-page PDF. A Kindle import brings hundreds of words at once, and
//  until now only 1,000 were measured (`PerformanceBaselineTests`).
//
//  Like the baseline they measure, they don't assert, and they only run
//  when asked: `TEST_RUNNER_RELL_LARGE_LIBRARY=1 make ci-test` (or
//  RELL_LARGE_LIBRARY=1 in the scheme) — the fixtures take a while to build.
//  The numbers go into ROADMAP.md.
//

import AppKit
import PDFKit
import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class LargeLibraryTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RELL_LARGE_LIBRARY"] == "1",
                          "Large-library measurements run on request (RELL_LARGE_LIBRARY=1)")
    }

    private var options: XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        return options
    }

    // MARK: - Fixtures

    private static let wordList: [String] = {
        let roots = ["light", "run", "fair", "bank", "close", "lead", "wind", "tear", "present", "object",
                     "content", "record", "permit", "minute", "desert", "refuse", "row", "bow", "live", "read",
                     "overcome", "ricochet", "melancholy", "apprehension", "tenement", "squalor", "accustom",
                     "elude", "landlady", "peculiar", "untimely", "drowsy", "inquisitive", "hideous", "moorings"]
        let suffixes = ["", "s", "ed", "ing", "er", "ly", "ness", "ment", "ful", "less"]
        var words: [String] = []
        var index = 0
        while words.count < 5_000 {
            let root = roots[index % roots.count]
            let suffix = suffixes[(index / roots.count) % suffixes.count]
            words.append(index < roots.count * suffixes.count ? root + suffix : "\(root)\(suffix)\(index)")
            index += 1
        }
        return words
    }()

    /// 5,000 words: a third reviewed, some forgotten often, spread over 40
    /// books and 10 decks — the shape of a library after a Kindle import.
    private static let vocabulary: [SavedWord] = {
        let now = Date()
        return wordList.enumerated().map { index, term in
            let reviewed = index % 3 == 0
            return SavedWord(
                term: term,
                sentence: "She read the \(term) twice before she understood it.",
                pdfFilename: "Book \(index % 40)",
                tags: index % 5 == 0 ? ["Deck \(index % 10)"] : [],
                llmOutputs: [
                    ModuleType.meaningTR.rawValue: "anlam \(index)",
                    ModuleType.definitionEN.rawValue: String(repeating: "A definition. ", count: 12),
                ],
                savedAt: now.addingTimeInterval(-Double(index) * 3_600),
                reviewCount: reviewed ? 1 + index % 6 : 0,
                incorrectCount: reviewed ? index % 4 : 0,
                lastReviewedAt: reviewed ? now.addingTimeInterval(-Double(index % 30) * 86_400) : nil,
                reviewEvents: reviewed ? (0..<(1 + index % 6)).map {
                    ReviewEvent(date: now.addingTimeInterval(-Double($0 + 1) * 86_400), rating: $0 % 3 == 0 ? .again : .good)
                } : [],
                nextReviewAt: reviewed ? now.addingTimeInterval(Double(index % 20 - 5) * 86_400) : nil,
                stability: reviewed ? Double(1 + index % 30) : nil,
                difficulty: reviewed ? 5 : nil,
                language: Language.english.rawValue
            )
        }
    }()

    private static func chapter(seed: Int) -> String {
        let words = wordList
        var generator = SplitMix(seed: UInt64(seed))
        let filler = ["the", "night", "was", "quiet", "and", "she", "walked", "through", "old", "streets",
                      "while", "rain", "fell", "on", "roofs", "of", "town", "he", "thought", "about"]
        return (0..<240).map { _ in
            (0..<16).map { index in
                index % 6 == 2 ? words[Int(generator.next() % UInt64(words.count))] : filler[Int(generator.next() % UInt64(filler.count))]
            }.joined(separator: " ") + "."
        }.joined(separator: " ")
    }

    private static let pdfURL: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rell-large-1000.pdf")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { return url }
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10)]
        for page in 0..<1_000 {
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            NSAttributedString(string: String(chapter(seed: page).prefix(3_000)), attributes: attributes)
                .draw(in: CGRect(x: 54, y: 54, width: 504, height: 684))
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }()

    // MARK: - The word store

    func testLoadFiveThousandWords() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("saved_words.json")
        try JSONEncoder().encode(Self.vocabulary).write(to: url)
        var stores: [SavedWordsStore] = []
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            let store = SavedWordsStore(fileURL: url)
            XCTAssertEqual(store.words.count, 5_000)
            stores.append(store)
        }
    }

    /// One `measure` per test: XCTest aborts on a second.
    func testEncodeFiveThousandWords() async throws {
        measure(metrics: [XCTClockMetric()], options: options) {
            _ = try? JSONEncoder().encode(Self.vocabulary)
        }
    }

    // MARK: - The notebook

    func testNotebookSourcesAndStatuses() async throws {
        let words = Self.vocabulary
        measure(metrics: [XCTClockMetric()], options: options) {
            _ = WordNotebook.books(from: words)
            for source in [WordNotebook.Source.all, .waiting, .new, .struggling, .missingMeaning] {
                _ = WordNotebook.words(for: source, from: words)
            }
            _ = words.map { (WordStatus.of($0), WordPageModel.recallNow($0)) }
        }
    }

    func testFindWordsSavedTwice() async throws {
        let words = Self.vocabulary
        measure(metrics: [XCTClockMetric()], options: options) {
            _ = WordMerge.duplicates(in: words)
        }
    }

    // MARK: - The study room

    func testBuildAStudyQueue() async throws {
        let words = Self.vocabulary
        measure(metrics: [XCTClockMetric()], options: options) {
            _ = StudyPlan(size: 20, source: .all, newLimit: 5).queue(from: words)
            _ = StudyPlan(size: 20, source: .struggling, newLimit: 0).queue(from: words)
        }
    }

    // MARK: - Reading

    func testScanAChapterForFiveThousandSavedWords() async throws {
        let text = Self.chapter(seed: 7)
        let entries = Self.vocabulary.map { EncounterScanner.Entry(id: $0.id, term: $0.term) }
        measure(metrics: [XCTClockMetric()], options: options) {
            _ = EncounterScanner.scan(text: text, vocabulary: entries, language: .english)
        }
    }

    func testProfileAChapterAgainstFiveThousandWords() async throws {
        let text = Self.chapter(seed: 8)
        let keys = Set(Self.wordList)
        measure(metrics: [XCTClockMetric()], options: options) {
            _ = LexicalProfileBuilder.profile(text: text, language: .english, masteredKeys: keys, learningKeys: [])
        }
    }

    func testOpenAThousandPagePDFAndReadEveryPage() async throws {
        let url = Self.pdfURL
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            guard let document = PDFDocument(url: url) else { return XCTFail("PDF didn't open") }
            XCTAssertEqual(document.pageCount, 1_000)
            for index in 0..<document.pageCount { _ = document.page(at: index)?.string }
        }
    }
}

/// SplitMix64 — reproducible fixtures without a dependency.
private struct SplitMix {
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
