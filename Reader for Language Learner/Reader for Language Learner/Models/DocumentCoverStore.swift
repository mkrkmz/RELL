//
//  DocumentCoverStore.swift
//  Reader for Language Learner
//
//  Renders and caches first-page cover thumbnails for PDFs shown on the
//  dashboard. Covers are rendered off the main thread, kept in an NSCache,
//  and persisted as PNGs under Application Support/RELL/covers/ so app
//  restarts don't re-render. A stale disk entry (PDF modified after the
//  cover was written) is re-rendered.
//

import AppKit
import CryptoKit
import Foundation
import PDFKit

@MainActor
@Observable
final class DocumentCoverStore {
    /// Bumps whenever a new cover lands so SwiftUI re-queries `cover(for:)`.
    private(set) var revision = 0

    @ObservationIgnored private let memoryCache = NSCache<NSString, NSImage>()
    @ObservationIgnored private var inFlight: Set<String> = []
    @ObservationIgnored private let coversDirectory: URL?

    /// Render size in points; large enough for the hero card at 2x.
    nonisolated static let renderSize = CGSize(width: 240, height: 320)

    init(coversDirectory customDirectory: URL? = nil) {
        if let customDirectory {
            coversDirectory = customDirectory
        } else {
            coversDirectory = FileManager.default.rellAppSupportDirectory()?
                .appendingPathComponent("covers", isDirectory: true)
        }
        if let coversDirectory {
            try? FileManager.default.createDirectory(at: coversDirectory, withIntermediateDirectories: true)
        }
    }

    /// Returns the cached cover, if one is already in memory.
    /// Call `requestCover(for:)` to load or render it asynchronously.
    func cover(for path: String) -> NSImage? {
        memoryCache.object(forKey: path as NSString)
    }

    /// Stores an externally supplied cover image (e.g. an EPUB's declared
    /// cover). Written to the same disk cache `requestCover` reads, so it
    /// survives restarts without re-extraction.
    func storeCover(imageData: Data, for path: String) {
        guard let image = NSImage(data: imageData),
              image.size.width > 0, image.size.height > 0 else { return }
        if let cacheURL = coverCacheURL(for: path) {
            try? imageData.write(to: cacheURL, options: .atomic)
        }
        memoryCache.setObject(image, forKey: path as NSString)
        revision += 1
    }

    /// Loads the cover from disk or renders it from the PDF's first page.
    /// Safe to call repeatedly; duplicate requests for the same path are ignored.
    func requestCover(for path: String) {
        guard memoryCache.object(forKey: path as NSString) == nil,
              !inFlight.contains(path) else { return }
        inFlight.insert(path)

        let cacheURL = coverCacheURL(for: path)
        Task.detached(priority: .utility) {
            let image = Self.loadOrRender(pdfPath: path, cacheURL: cacheURL)
            await MainActor.run {
                self.inFlight.remove(path)
                if let image {
                    self.memoryCache.setObject(image, forKey: path as NSString)
                    self.revision += 1
                }
            }
        }
    }

    // MARK: - Rendering (off main thread)

    private nonisolated static func loadOrRender(pdfPath: String, cacheURL: URL?) -> NSImage? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: pdfPath) else { return nil }

        // Disk hit, still fresh → use it.
        if let cacheURL,
           fileManager.fileExists(atPath: cacheURL.path),
           modificationDate(of: cacheURL.path) ?? .distantPast >= modificationDate(of: pdfPath) ?? .distantFuture,
           let cached = NSImage(contentsOf: cacheURL) {
            return cached
        }

        guard let document = PDFDocument(url: URL(fileURLWithPath: pdfPath)),
              let firstPage = document.page(at: 0) else { return nil }

        let image = firstPage.thumbnail(of: renderSize, for: .cropBox)
        guard image.size.width > 0, image.size.height > 0 else { return nil }

        if let cacheURL,
           let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            try? png.write(to: cacheURL, options: .atomic)
        }

        return image
    }

    private nonisolated static func modificationDate(of path: String) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
    }

    private func coverCacheURL(for path: String) -> URL? {
        guard let coversDirectory else { return nil }
        let digest = SHA256.hash(data: Data(path.utf8))
        let name = digest.map { String(format: "%02x", $0) }.prefix(16).joined()
        return coversDirectory.appendingPathComponent("\(name).png")
    }
}
