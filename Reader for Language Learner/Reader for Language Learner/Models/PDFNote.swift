//
//  PDFNote.swift
//  Reader for Language Learner
//

import Foundation
import Observation
import os

enum PDFNoteCategory: String, Codable, CaseIterable, Identifiable {
    case vocabulary
    case insight
    case review

    var id: String { rawValue }

    var label: String {
        switch self {
        case .vocabulary: return "Vocabulary"
        case .insight: return "Insight"
        case .review: return "Review"
        }
    }

    var icon: String {
        switch self {
        case .vocabulary: return "text.book.closed"
        case .insight: return "lightbulb"
        case .review: return "clock.arrow.circlepath"
        }
    }
}

enum PDFNoteFilter: String, CaseIterable, Identifiable {
    case all
    case vocabulary
    case insight
    case review

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .vocabulary: return "Vocabulary"
        case .insight: return "Insight"
        case .review: return "Review"
        }
    }

    var category: PDFNoteCategory? {
        switch self {
        case .all: return nil
        case .vocabulary: return .vocabulary
        case .insight: return .insight
        case .review: return .review
        }
    }
}

struct PDFHighlightRect: Codable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

struct PDFNote: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var pdfFilename: String
    var pageIndex: Int
    var pageLabel: String
    var selectedText: String
    var contextSentence: String
    var note: String
    var category: PDFNoteCategory
    var highlightRects: [PDFHighlightRect]
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    enum CodingKeys: String, CodingKey {
        case id
        case pdfFilename
        case pageIndex
        case pageLabel
        case selectedText
        case contextSentence
        case note
        case category
        case highlightRects
        case createdAt
        case updatedAt
    }

    init(
        id: UUID = UUID(),
        pdfFilename: String,
        pageIndex: Int,
        pageLabel: String,
        selectedText: String,
        contextSentence: String,
        note: String,
        category: PDFNoteCategory = .vocabulary,
        highlightRects: [PDFHighlightRect],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.pdfFilename = pdfFilename
        self.pageIndex = pageIndex
        self.pageLabel = pageLabel
        self.selectedText = selectedText
        self.contextSentence = contextSentence
        self.note = note
        self.category = category
        self.highlightRects = highlightRects
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        pdfFilename = try container.decode(String.self, forKey: .pdfFilename)
        pageIndex = try container.decode(Int.self, forKey: .pageIndex)
        pageLabel = try container.decode(String.self, forKey: .pageLabel)
        selectedText = try container.decode(String.self, forKey: .selectedText)
        contextSentence = try container.decodeIfPresent(String.self, forKey: .contextSentence) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        category = try container.decodeIfPresent(PDFNoteCategory.self, forKey: .category) ?? .vocabulary
        highlightRects = try container.decodeIfPresent([PDFHighlightRect].self, forKey: .highlightRects) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }
}

@MainActor
@Observable
final class PDFNoteStore {

    private(set) var notes: [PDFNote] = []
    var draftNote: PDFNote?

    private let fileURL: URL

    init(fileURL customFileURL: URL? = nil) {
        if let customFileURL {
            self.fileURL = customFileURL
            self.notes = Self.load(from: customFileURL)
            return
        }

        guard let dir = FileManager.default.rellAppSupportDirectory() else {
            self.fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("pdf_notes.json")
            self.notes = []
            return
        }

        self.fileURL = dir.appendingPathComponent("pdf_notes.json")
        self.notes = Self.load(from: fileURL)
    }

    func notes(for filename: String) -> [PDFNote] {
        notes
            .filter { $0.pdfFilename == filename }
            .sorted { lhs, rhs in
                if lhs.pageIndex == rhs.pageIndex {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.pageIndex < rhs.pageIndex
            }
    }

    func filteredNotes(
        for filename: String,
        searchText: String = "",
        filter: PDFNoteFilter = .all
    ) -> [PDFNote] {
        let normalizedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return notes(for: filename).filter { note in
            let matchesCategory = filter.category.map { note.category == $0 } ?? true
            guard matchesCategory else { return false }
            guard !normalizedQuery.isEmpty else { return true }

            let haystack = [
                note.selectedText,
                note.note,
                note.contextSentence,
                note.pageLabel,
                note.category.label
            ]
                .joined(separator: "\n")
                .localizedCaseInsensitiveContains(normalizedQuery)
            return haystack
        }
    }

    func count(for filename: String?) -> Int {
        guard let filename else { return 0 }
        return notes.filter { $0.pdfFilename == filename }.count
    }

    func count(for filename: String?, category: PDFNoteCategory) -> Int {
        guard let filename else { return 0 }
        return notes.filter { $0.pdfFilename == filename && $0.category == category }.count
    }

    func note(matching selectedText: String, on filename: String, pageIndex: Int) -> PDFNote? {
        notes.first {
            $0.pdfFilename == filename
                && $0.pageIndex == pageIndex
                && $0.selectedText.caseInsensitiveCompare(selectedText) == .orderedSame
        }
    }

    func startDraft(_ note: PDFNote) {
        draftNote = note
    }

    func cancelDraft() {
        draftNote = nil
    }

    func saveDraft(_ note: PDFNote) {
        add(note)
        draftNote = nil
    }

    func add(_ note: PDFNote) {
        notes.insert(note, at: 0)
        save()
    }

    func update(_ note: PDFNote) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        var updated = note
        updated.updatedAt = Date()
        notes[index] = updated
        save()
    }

    func remove(id: UUID) {
        notes.removeAll { $0.id == id }
        save()
    }

    private func save() {
        do {
            try RELLJSONStore.save(notes, to: fileURL, storeName: "PDFNoteStore")
        } catch {
            AppLogger.persistence.error("PDFNoteStore save failed at \(self.fileURL.path, privacy: .private): \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func load(from url: URL) -> [PDFNote] {
        RELLJSONStore.load([PDFNote].self, from: url, storeName: "PDFNoteStore", defaultValue: [])
    }
}
