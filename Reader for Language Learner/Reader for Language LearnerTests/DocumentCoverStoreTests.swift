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

    /// Waits (up to 10 s) for a render to land — the store's revision moves
    /// only when a cover was made — then returns the cover if the memory
    /// cache still has it.
    ///
    /// v18 S6: the memory cache is an `NSCache`, which the system may empty
    /// at any moment under memory pressure, as during the full suite. Polling
    /// the cache alone made this class's first test fail now and then though
    /// the cover had rendered (green alone and on CI); the revision and the
    /// PNG on disk say it did.
    @discardableResult
    private func waitForRender(in store: DocumentCoverStore, path: String, from revision: Int = 0) async -> NSImage? {
        for _ in 0..<200 where store.revision == revision {
            try? await Task.sleep(for: .milliseconds(50))
        }
        return store.cover(for: path)
    }

    private func cachedPNGs(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "png" }
    }

    func testRendersCoverForValidPDF() async throws {
        let coversDir = makeCoversDirectory()
        let pdfURL = try makeTempPDF()
        let store = makeStore(coversDirectory: coversDir)

        store.requestCover(for: pdfURL.path)
        await waitForRender(in: store, path: pdfURL.path)

        XCTAssertEqual(store.revision, 1, "A valid one-page PDF should produce a cover")
        let png = try XCTUnwrap(cachedPNGs(in: coversDir).first)
        XCTAssertGreaterThan(NSImage(contentsOf: png)?.size.width ?? 0, 0)
    }

    func testWritesCoverToDiskCache() async throws {
        let coversDir = makeCoversDirectory()
        let pdfURL = try makeTempPDF()
        let store = makeStore(coversDirectory: coversDir)

        store.requestCover(for: pdfURL.path)
        await waitForRender(in: store, path: pdfURL.path)

        XCTAssertEqual(try cachedPNGs(in: coversDir).count, 1, "Cover should be persisted as a single PNG")
    }

    func testSecondStoreLoadsFromDiskCache() async throws {
        let coversDir = makeCoversDirectory()
        let pdfURL = try makeTempPDF()

        let first = makeStore(coversDirectory: coversDir)
        first.requestCover(for: pdfURL.path)
        await waitForRender(in: first, path: pdfURL.path)
        XCTAssertEqual(try cachedPNGs(in: coversDir).count, 1)

        // A fresh store (empty memory cache) should resolve from disk.
        let second = makeStore(coversDirectory: coversDir)
        second.requestCover(for: pdfURL.path)
        await waitForRender(in: second, path: pdfURL.path)
        XCTAssertEqual(second.revision, 1, "loaded from the PNG on disk")
    }

    func testMissingFileProducesNoCover() async {
        let store = makeStore(coversDirectory: makeCoversDirectory())
        let bogusPath = "/tmp/does_not_exist_\(UUID().uuidString).pdf"

        store.requestCover(for: bogusPath)
        try? await Task.sleep(for: .milliseconds(300))

        XCTAssertNil(store.cover(for: bogusPath))
    }
}
