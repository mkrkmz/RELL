//
//  EPUBNote.swift
//  Reader for Language Learner
//
//  Model + store for standalone notes inside EPUBs — the counterpart of
//  PDFNote for the reflowable world. Positioned the same way as
//  EPUBBookmark (chapter index + scroll fraction); a note is "a thought at
//  this point in the book", not an annotation on specific text (that's a
//  highlight note).
//

import Foundation
import Observation
import os

// MARK: - Model

struct EPUBNote: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var epubFilename: String
    var chapterIndex: Int
    /// 0…1 scroll progress within the chapter at creation time.
    var scrollFraction: Double
    var text: String
    var createdAt: Date = Date()
}

// MARK: - Store

@MainActor
@Observable
final class EPUBNoteStore {

    private(set) var notes: [EPUBNote] = []

    private let fileURL: URL

    init(fileURL customFileURL: URL? = nil) {
        if let customFileURL {
            self.fileURL = customFileURL
            self.notes = Self.load(from: customFileURL)
            return
        }

        guard let dir = FileManager.default.rellAppSupportDirectory() else {
            self.fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("epub_notes.json")
            self.notes = []
            return
        }

        self.fileURL = dir.appendingPathComponent("epub_notes.json")
        self.notes = Self.load(from: fileURL)
    }

    // MARK: Queries

    func notes(for filename: String) -> [EPUBNote] {
        notes
            .filter { $0.epubFilename == filename }
            .sorted { lhs, rhs in
                lhs.chapterIndex == rhs.chapterIndex
                    ? lhs.createdAt > rhs.createdAt
                    : lhs.chapterIndex < rhs.chapterIndex
            }
    }

    func count(for filename: String?) -> Int {
        guard let filename else { return 0 }
        return notes.filter { $0.epubFilename == filename }.count
    }

    // MARK: Mutations

    func add(_ note: EPUBNote) {
        notes.insert(note, at: 0)
        save()
    }

    func remove(id: UUID) {
        notes.removeAll { $0.id == id }
        save()
    }

    func updateText(id: UUID, text: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        save()
    }

    // MARK: Persistence

    private func save() {
        do {
            try RELLJSONStore.save(notes, to: fileURL, storeName: "EPUBNoteStore")
        } catch {
            AppLogger.persistence.error("EPUBNoteStore save failed at \(self.fileURL.path, privacy: .private): \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func load(from url: URL) -> [EPUBNote] {
        RELLJSONStore.load([EPUBNote].self, from: url, storeName: "EPUBNoteStore", defaultValue: [])
    }
}
