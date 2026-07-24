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
    /// Pinned documents survive `RecentDocumentStore.trim()` regardless of age.
    var isPinned: Bool
    /// A single named collection this document belongs to, or nil.
    var collectionID: UUID?

    init(
        id: UUID = UUID(),
        path: String,
        filename: String,
        lastOpenedAt: Date = Date(),
        lastPageIndex: Int? = nil,
        pageCount: Int? = nil,
        isPinned: Bool = false,
        collectionID: UUID? = nil
    ) {
        self.id = id
        self.path = path
        self.filename = filename
        self.lastOpenedAt = lastOpenedAt
        self.lastPageIndex = lastPageIndex
        self.pageCount = pageCount
        self.isPinned = isPinned
        self.collectionID = collectionID
    }

    private enum CodingKeys: String, CodingKey {
        case id, path, filename, lastOpenedAt, lastPageIndex, pageCount, isPinned, collectionID
    }

    /// Custom decode: `isPinned`/`collectionID` were added after the first
    /// persisted snapshots (v1.24) — a non-Optional property with no custom
    /// decode would make every pre-v1.24 entry fail to decode and wipe the
    /// whole library, since array decoding aborts on the first bad element.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        path = try container.decode(String.self, forKey: .path)
        filename = try container.decode(String.self, forKey: .filename)
        lastOpenedAt = try container.decode(Date.self, forKey: .lastOpenedAt)
        lastPageIndex = try container.decodeIfPresent(Int.self, forKey: .lastPageIndex)
        pageCount = try container.decodeIfPresent(Int.self, forKey: .pageCount)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        collectionID = try container.decodeIfPresent(UUID.self, forKey: .collectionID)
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

/// A named, single-membership group of library documents ("folder" semantics —
/// a document belongs to at most one collection at a time).
struct DocumentCollection: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    let createdAt: Date

    init(id: UUID = UUID(), name: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

@MainActor
@Observable
final class RecentDocumentStore {
    private(set) var documents: [RecentDocument] = []
    private(set) var collections: [DocumentCollection] = []

    private let fileURL: URL
    private let collectionsFileURL: URL
    private let writer: DebouncedFileWriter
    private let collectionsWriter: DebouncedFileWriter
    private let maxDocuments = 48

    init(fileURL customFileURL: URL? = nil) {
        let docs = DebouncedFileWriter.forAppSupport(
            filename: "recent_documents.json",
            storeName: "RecentDocumentStore",
            customFileURL: customFileURL
        )
        // In the test (custom-URL) path each instance gets its own sibling
        // collections file; the app path resolves the shared one.
        let collectionsCustom = customFileURL.map(Self.derivedCollectionsURL(for:))
        let cols = DebouncedFileWriter.forAppSupport(
            filename: "library_collections.json",
            storeName: "DocumentCollectionStore",
            customFileURL: collectionsCustom
        )
        self.fileURL = docs.url
        self.writer = docs.writer
        self.collectionsFileURL = cols.url
        self.collectionsWriter = cols.writer
        self.documents = docs.canLoad ? Self.load(from: docs.url) : []
        self.collections = cols.canLoad ? Self.loadCollections(from: cols.url) : []
    }

    /// Sibling path for a custom (typically test) documents file, so each
    /// test instance gets its own collections file without a second param
    /// at every call site — e.g. `<uuid>.json` → `<uuid>-collections.json`.
    private static func derivedCollectionsURL(for documentsURL: URL) -> URL {
        let base = documentsURL.deletingPathExtension().lastPathComponent
        return documentsURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(base)-collections.json")
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

    /// Empties the whole recent-documents list ("Open Recent ▸ Clear Menu").
    /// The files themselves are untouched.
    func clear() {
        let removed = documents
        documents.removeAll()
        save()
        removed.forEach { SpotlightIndexer.removeDocument(path: $0.path) }
    }

    // MARK: - Pin

    func setPinned(_ pinned: Bool, id: UUID) {
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        documents[index].isPinned = pinned
        save()
    }

    // MARK: - Collections

    @discardableResult
    func createCollection(name: String) -> DocumentCollection {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let collection = DocumentCollection(name: trimmed.isEmpty ? String(localized: "Untitled") : trimmed)
        collections.append(collection)
        saveCollections()
        return collection
    }

    func renameCollection(id: UUID, to name: String) {
        guard let index = collections.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        collections[index].name = trimmed
        saveCollections()
    }

    /// Deletes the collection; member documents fall back to "no collection"
    /// rather than being removed from the library.
    func deleteCollection(id: UUID) {
        collections.removeAll { $0.id == id }
        for index in documents.indices where documents[index].collectionID == id {
            documents[index].collectionID = nil
        }
        saveCollections()
        save()
    }

    /// Assigns a document to a collection, or removes it from one with `nil`.
    func assign(id: UUID, to collectionID: UUID?) {
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        documents[index].collectionID = collectionID
        save()
    }

    // MARK: - Trim

    /// Keeps the library from growing without bound. Pinned documents are
    /// exempt; among the rest, the most recently opened survive.
    private func trim() {
        guard documents.count > maxDocuments else { return }
        let pinned = documents.filter { $0.isPinned }
        let unpinned = documents
            .filter { !$0.isPinned }
            .sorted { $0.lastOpenedAt > $1.lastOpenedAt }
        let keepCount = max(0, maxDocuments - pinned.count)
        let keptIDs = Set(unpinned.prefix(keepCount).map(\.id))
        documents.removeAll { !$0.isPinned && !keptIDs.contains($0.id) }
    }

    // MARK: - Persistence

    private func save() {
        writer.schedule { [documents] in try JSONEncoder().encode(documents) }
    }

    private func saveCollections() {
        collectionsWriter.schedule { [collections] in try JSONEncoder().encode(collections) }
    }

    private static func load(from url: URL) -> [RecentDocument] {
        RELLJSONStore.load([RecentDocument].self, from: url, storeName: "RecentDocumentStore", defaultValue: [])
    }

    private static func loadCollections(from url: URL) -> [DocumentCollection] {
        RELLJSONStore.load([DocumentCollection].self, from: url, storeName: "DocumentCollectionStore", defaultValue: [])
    }
}
