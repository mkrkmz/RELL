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

    init(
        id: UUID = UUID(),
        path: String,
        filename: String,
        lastOpenedAt: Date = Date(),
        lastPageIndex: Int? = nil
    ) {
        self.id = id
        self.path = path
        self.filename = filename
        self.lastOpenedAt = lastOpenedAt
        self.lastPageIndex = lastPageIndex
    }

    var url: URL {
        URL(fileURLWithPath: path)
    }

    var pageLabel: String {
        if let lastPageIndex {
            return "Page \(lastPageIndex + 1)"
        }
        return "Start reading"
    }
}

@MainActor
@Observable
final class RecentDocumentStore {
    private(set) var documents: [RecentDocument] = []

    private let fileURL: URL
    private let maxDocuments = 12

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

    func updateLastPage(for url: URL, pageIndex: Int) {
        let path = url.path
        guard let index = documents.firstIndex(where: { $0.path == path }) else { return }
        documents[index].lastPageIndex = pageIndex
        documents[index].lastOpenedAt = Date()
        save()
    }

    func removeMissingDocuments() {
        documents.removeAll { !FileManager.default.fileExists(atPath: $0.path) }
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
