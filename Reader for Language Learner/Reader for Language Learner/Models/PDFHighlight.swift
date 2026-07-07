//
//  PDFHighlight.swift
//  Reader for Language Learner
//
//  Model + store for user-created persistent text highlights.
//  Reuses PDFHighlightRect (defined in PDFNote.swift) for page-space geometry.
//

import AppKit
import Foundation
import Observation
import os

// MARK: - Color

enum HighlightColor: String, Codable, CaseIterable, Identifiable {
    case yellow
    case green
    case blue
    case pink
    case purple

    var id: String { rawValue }

    var label: String {
        switch self {
        case .yellow: return "Yellow"
        case .green:  return "Green"
        case .blue:   return "Blue"
        case .pink:   return "Pink"
        case .purple: return "Purple"
        }
    }

    /// Base color for both the annotation fill and the sidebar swatch.
    var nsColor: NSColor {
        switch self {
        case .yellow: return .systemYellow
        case .green:  return .systemGreen
        case .blue:   return .systemBlue
        case .pink:   return .systemPink
        case .purple: return .systemPurple
        }
    }
}

// MARK: - Model

struct PDFHighlight: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var pdfFilename: String
    var pageIndex: Int
    var pageLabel: String
    var selectedText: String
    var colorRaw: String
    var highlightRects: [PDFHighlightRect]
    var createdAt: Date = Date()
    /// Optional user annotation attached to the highlight (added in 1.10;
    /// absent from older persistence files, hence the custom decoder).
    var note: String = ""

    var color: HighlightColor {
        HighlightColor(rawValue: colorRaw) ?? .yellow
    }

    init(
        id: UUID = UUID(),
        pdfFilename: String,
        pageIndex: Int,
        pageLabel: String,
        selectedText: String,
        colorRaw: String,
        highlightRects: [PDFHighlightRect],
        createdAt: Date = Date(),
        note: String = ""
    ) {
        self.id = id
        self.pdfFilename = pdfFilename
        self.pageIndex = pageIndex
        self.pageLabel = pageLabel
        self.selectedText = selectedText
        self.colorRaw = colorRaw
        self.highlightRects = highlightRects
        self.createdAt = createdAt
        self.note = note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        pdfFilename = try container.decode(String.self, forKey: .pdfFilename)
        pageIndex = try container.decode(Int.self, forKey: .pageIndex)
        pageLabel = try container.decode(String.self, forKey: .pageLabel)
        selectedText = try container.decode(String.self, forKey: .selectedText)
        colorRaw = try container.decode(String.self, forKey: .colorRaw)
        highlightRects = try container.decode([PDFHighlightRect].self, forKey: .highlightRects)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

// MARK: - Store

@MainActor
@Observable
final class PDFHighlightStore {

    private(set) var highlights: [PDFHighlight] = []

    private let fileURL: URL

    init(fileURL customFileURL: URL? = nil) {
        if let customFileURL {
            self.fileURL = customFileURL
            self.highlights = Self.load(from: customFileURL)
            return
        }

        guard let dir = FileManager.default.rellAppSupportDirectory() else {
            self.fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("pdf_highlights.json")
            self.highlights = []
            return
        }

        self.fileURL = dir.appendingPathComponent("pdf_highlights.json")
        self.highlights = Self.load(from: fileURL)
    }

    // MARK: Queries

    func highlights(for filename: String) -> [PDFHighlight] {
        highlights
            .filter { $0.pdfFilename == filename }
            .sorted { lhs, rhs in
                lhs.pageIndex == rhs.pageIndex
                    ? lhs.createdAt > rhs.createdAt
                    : lhs.pageIndex < rhs.pageIndex
            }
    }

    func count(for filename: String?) -> Int {
        guard let filename else { return 0 }
        return highlights.filter { $0.pdfFilename == filename }.count
    }

    // MARK: Mutations

    func add(_ highlight: PDFHighlight) {
        highlights.insert(highlight, at: 0)
        save()
        notifyChange()
    }

    func remove(id: UUID) {
        highlights.removeAll { $0.id == id }
        save()
        notifyChange()
    }

    func updateColor(id: UUID, color: HighlightColor) {
        guard let index = highlights.firstIndex(where: { $0.id == id }) else { return }
        highlights[index].colorRaw = color.rawValue
        save()
        notifyChange()
    }

    /// Notes aren't rendered on the page, so no annotation refresh is needed.
    func updateNote(id: UUID, note: String) {
        guard let index = highlights.firstIndex(where: { $0.id == id }) else { return }
        highlights[index].note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        save()
    }

    /// Lets the PDF coordinator re-render annotations regardless of SwiftUI
    /// observation, which doesn't reliably reach an NSViewRepresentable.
    private func notifyChange() {
        NotificationCenter.default.post(name: .pdfHighlightsChanged, object: nil)
    }

    // MARK: Persistence

    private func save() {
        do {
            try RELLJSONStore.save(highlights, to: fileURL, storeName: "PDFHighlightStore")
        } catch {
            AppLogger.persistence.error("PDFHighlightStore save failed at \(self.fileURL.path, privacy: .private): \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func load(from url: URL) -> [PDFHighlight] {
        RELLJSONStore.load([PDFHighlight].self, from: url, storeName: "PDFHighlightStore", defaultValue: [])
    }
}

extension Notification.Name {
    static let pdfHighlightsChanged = Notification.Name("pdfHighlightsChanged")
}
