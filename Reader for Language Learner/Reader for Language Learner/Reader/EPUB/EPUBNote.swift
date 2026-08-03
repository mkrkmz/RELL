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
final class EPUBNoteStore: UndoableStore {

    private(set) var notes: [EPUBNote] = []
    @ObservationIgnored weak var undoManager: UndoManager?

    private let fileURL: URL
    private let writer: DebouncedFileWriter

    init(fileURL customFileURL: URL? = nil) {
        let resolved = DebouncedFileWriter.forAppSupport(
            filename: "epub_notes.json",
            storeName: "EPUBNoteStore",
            customFileURL: customFileURL
        )
        self.fileURL = resolved.url
        self.writer = resolved.writer
        self.notes = resolved.canLoad ? Self.load(from: resolved.url) : []
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
        registerUndo("Add Note") { $0.remove(id: note.id) }
    }

    func remove(id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        let removed = notes.remove(at: index)
        save()
        registerUndo("Delete Note") { $0.reinsert(removed, at: index) }
    }

    private func reinsert(_ note: EPUBNote, at index: Int) {
        notes.insert(note, at: min(index, notes.count))
        save()
        registerUndo("Delete Note") { $0.remove(id: note.id) }
    }

    func updateText(id: UUID, text: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        let previous = notes[index].text
        notes[index].text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        save()
        registerUndo("Edit Note") { $0.updateText(id: id, text: previous) }
    }

    // MARK: Persistence

    private func save() {
        writer.schedule { [notes] in try JSONEncoder().encode(notes) }
    }

    private static func load(from url: URL) -> [EPUBNote] {
        RELLJSONStore.load([EPUBNote].self, from: url, storeName: "EPUBNoteStore", defaultValue: [])
    }
}
