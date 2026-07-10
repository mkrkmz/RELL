//
//  RecentDocument.swift
//  Reader for Language Learner
//

import Foundation
import Observation
import os

struct RecentDocument: Identifiable, Codable, Hashable {
    let id: UUID
    var path: String
    var filename: String
    var lastOpenedAt: Date
    var lastPageIndex: Int?
    var pageCount: Int?

    init(
        id: UUID = UUID(),
        path: String,
        filename: String,
        lastOpenedAt: Date = Date(),
        lastPageIndex: Int? = nil,
        pageCount: Int? = nil
    ) {
        self.id = id
        self.path = path
        self.filename = filename
        self.lastOpenedAt = lastOpenedAt
        self.lastPageIndex = lastPageIndex
        self.pageCount = pageCount
    }

    var url: URL {
        URL(fileURLWithPath: path)
    }

    /// Drives the "Chapter" vs "Page" wording below — the store only ever
    /// records a path, not a document kind, so the extension is the signal.
    var isEPUB: Bool {
        (path as NSString).pathExtension.lowercased() == "epub"
    }

    /// Filename cleaned for display. `registerOpen` stores extension-less
    /// names, but entries persisted by older versions kept the extension —
    /// strip a trailing .pdf/.epub defensively, and read underscores as spaces.
    var displayTitle: String {
        var title = filename
        for ext in [".pdf", ".epub"] {
            title = title.replacingOccurrences(
                of: ext, with: "", options: [.caseInsensitive, .anchored, .backwards]
            )
        }
        return title.replacingOccurrences(of: "_", with: " ")
    }

    var pageLabel: String {
        guard let lastPageIndex else { return String(localized: "Start reading") }
        let number = lastPageIndex + 1
        if let pageCount, pageCount > 0 {
            return isEPUB
                ? String(localized: "Chapter \(number) of \(pageCount)")
                : String(localized: "Page \(number) of \(pageCount)")
        }
        return isEPUB
            ? String(localized: "Chapter \(number)")
            : String(localized: "Page \(number)")
    }

    /// Fraction of the document read (0...1), when both page values are known.
    var readingProgress: Double? {
        guard let lastPageIndex, let pageCount, pageCount > 0 else { return nil }
        return min(1, Double(lastPageIndex + 1) / Double(pageCount))
    }
}

@MainActor
@Observable
final class RecentDocumentStore {
    private(set) var documents: [RecentDocument] = []

    private let fileURL: URL
    private let maxDocuments = 48

    init(fileURL customFileURL: URL? = nil) {
        if let customFileURL {
            self.fileURL = customFileURL
            self.documents = Self.load(from: customFileURL)
            return
        }

        guard let dir = FileManager.default.rellAppSupportDirectory() else {
            self.fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("recent_documents.json")
            self.documents = []
            return
        }

        self.fileURL = dir.appendingPathComponent("recent_documents.json")
        self.documents = Self.load(from: fileURL)
    }

    var recentDocuments: [RecentDocument] {
        documents
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .sorted { $0.lastOpenedAt > $1.lastOpenedAt }
    }

    func registerOpen(url: URL) {
        let path = url.path
        let filename = url.deletingPathExtension().lastPathComponent
        if let index = documents.firstIndex(where: { $0.path == path }) {
            documents[index].filename = filename
            documents[index].lastOpenedAt = Date()
        } else {
            documents.insert(
                RecentDocument(path: path, filename: filename),
                at: 0
            )
        }
        trim()
        save()
        SpotlightIndexer.indexDocument(at: url)
    }

    func updateLastPage(for url: URL, pageIndex: Int, pageCount: Int? = nil) {
        let path = url.path
        guard let index = documents.firstIndex(where: { $0.path == path }) else { return }
        documents[index].lastPageIndex = pageIndex
        if let pageCount, pageCount > 0 {
            documents[index].pageCount = pageCount
        }
        documents[index].lastOpenedAt = Date()
        save()
    }

    func removeMissingDocuments() {
        let missing = documents.filter { !FileManager.default.fileExists(atPath: $0.path) }
        documents.removeAll { !FileManager.default.fileExists(atPath: $0.path) }
        save()
        missing.forEach { SpotlightIndexer.removeDocument(path: $0.path) }
    }

    /// Removes a single document from the library (the file itself is untouched).
    func remove(id: UUID) {
        let removed = documents.filter { $0.id == id }
        documents.removeAll { $0.id == id }
        save()
        removed.forEach { SpotlightIndexer.removeDocument(path: $0.path) }
    }

    private func trim() {
        if documents.count > maxDocuments {
            documents = Array(documents.prefix(maxDocuments))
        }
    }

    private func save() {
        do {
            try RELLJSONStore.save(documents, to: fileURL, storeName: "RecentDocumentStore")
        } catch {
            AppLogger.persistence.error("RecentDocumentStore save failed at \(self.fileURL.path, privacy: .private): \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func load(from url: URL) -> [RecentDocument] {
        RELLJSONStore.load([RecentDocument].self, from: url, storeName: "RecentDocumentStore", defaultValue: [])
    }
}
