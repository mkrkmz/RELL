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

    private func waitForCover(in store: DocumentCoverStore, path: String) async -> NSImage? {
        for _ in 0..<100 {
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
