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

    var pageLabel: String {
        guard let lastPageIndex else { return "Start reading" }
        if let pageCount, pageCount > 0 {
            return "Page \(lastPageIndex + 1) of \(pageCount)"
        }
        return "Page \(lastPageIndex + 1)"
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
        documents.removeAll { !FileManager.default.fileExists(atPath: $0.path) }
        save()
    }

    /// Removes a single document from the library (the file itself is untouched).
    func remove(id: UUID) {
        documents.removeAll { $0.id == id }
        save()
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
