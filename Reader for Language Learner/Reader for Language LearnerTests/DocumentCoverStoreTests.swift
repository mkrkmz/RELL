//
//  DocumentCoverStoreTests.swift
//  Reader for Language LearnerTests
//

import PDFKit
import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class DocumentCoverStoreTests: XCTestCase {
    private static var retainedStores: [DocumentCoverStore] = []

    private func makeCoversDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("covers_test_\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func makeStore(coversDirectory: URL) -> DocumentCoverStore {
        let store = DocumentCoverStore(coversDirectory: coversDirectory)
        Self.retainedStores.append(store)
        return store
    }

    /// Creates a real single-page PDF on disk via PDFKit.
    private func makeTempPDF() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cover_source_\(UUID().uuidString).pdf")

        let pdfData = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 200, height: 280)
        let consumer = try XCTUnwrap(CGDataConsumer(data: pdfData as CFMutableData))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        context.setFillColor(NSColor.systemBlue.cgColor)
        context.fill(mediaBox)
        context.endPDFPage()
        context.closePDF()

        try (pdfData as Data).write(to: url, options: .atomic)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    /// v18 S6: the store renders at utility priority, and the first render
    /// in the process loads PDFKit from disk. Under the full suite's load,
    /// macOS throttled that low-priority I/O so long that this class's first
    /// test sometimes got no cover in 20 s (red in some full runs, green
    /// alone and on CI). One thumbnail drawn here at normal priority pays
    /// that cold start, so the tests time the store, not the disk.
    nonisolated override class func setUp() {
        super.setUp()
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 20, height: 20)
        if let consumer = CGDataConsumer(data: data as CFMutableData),
           let context = CGContext(consumer: consumer, mediaBox: &box, nil) {
            context.beginPDFPage(nil)
            context.endPDFPage()
            context.closePDF()
        }
        _ = PDFDocument(data: data as Data)?.page(at: 0)?.thumbnail(of: CGSize(width: 10, height: 10), for: .cropBox)
    }

    /// Up to 10 s, back as soon as the cover is there.
    private func waitForCover(in store: DocumentCoverStore, path: String) async -> NSImage? {
        for _ in 0..<200 {
            if let image = store.cover(for: path) { return image }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return store.cover(for: path)
    }

    func testRendersCoverForValidPDF() async throws {
        let coversDir = makeCoversDirectory()
        let pdfURL = try makeTempPDF()
        let store = makeStore(coversDirectory: coversDir)

        store.requestCover(for: pdfURL.path)
        let image = await waitForCover(in: store, path: pdfURL.path)

        XCTAssertNotNil(image, "A valid one-page PDF should produce a cover")
        XCTAssertGreaterThan(image?.size.width ?? 0, 0)
    }

    func testWritesCoverToDiskCache() async throws {
        let coversDir = makeCoversDirectory()
        let pdfURL = try makeTempPDF()
        let store = makeStore(coversDirectory: coversDir)

        store.requestCover(for: pdfURL.path)
        _ = await waitForCover(in: store, path: pdfURL.path)

        let cached = try FileManager.default.contentsOfDirectory(atPath: coversDir.path)
            .filter { $0.hasSuffix(".png") }
        XCTAssertEqual(cached.count, 1, "Cover should be persisted as a single PNG")
    }

    func testSecondStoreLoadsFromDiskCache() async throws {
        let coversDir = makeCoversDirectory()
        let pdfURL = try makeTempPDF()

        let first = makeStore(coversDirectory: coversDir)
        first.requestCover(for: pdfURL.path)
        _ = await waitForCover(in: first, path: pdfURL.path)

        // A fresh store (empty memory cache) should resolve from disk.
        let second = makeStore(coversDirectory: coversDir)
        second.requestCover(for: pdfURL.path)
        let image = await waitForCover(in: second, path: pdfURL.path)
        XCTAssertNotNil(image)
    }

    func testMissingFileProducesNoCover() async {
        let store = makeStore(coversDirectory: makeCoversDirectory())
        let bogusPath = "/tmp/does_not_exist_\(UUID().uuidString).pdf"

        store.requestCover(for: bogusPath)
        try? await Task.sleep(for: .milliseconds(300))

        XCTAssertNil(store.cover(for: bogusPath))
    }
}
