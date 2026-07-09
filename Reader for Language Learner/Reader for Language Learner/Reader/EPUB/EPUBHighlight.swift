//
//  EPUBHighlight.swift
//  Reader for Language Learner
//
//  Model + store for highlights inside EPUBs. Unlike PDFHighlight (which
//  anchors to page-space rects), reflowable EPUB text has no fixed geometry,
//  so the anchor is a text-quote selector: the exact quote plus short
//  prefix/suffix context and a same-session text offset, all computed by
//  the injected JS against a text-node walk that stays stable across font
//  size and window-size reflow (see EPUBReaderView's highlight scripts).
//

import AppKit
import Foundation
import Observation
import os

// MARK: - Model

struct EPUBHighlight: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var epubFilename: String
    var chapterIndex: Int
    var chapterPath: String
    /// The exact selected text — also the primary re-anchor fallback.
    var quote: String
    /// ~24 characters immediately before/after the quote in the chapter's
    /// rendered text, used to disambiguate repeated occurrences.
    var prefix: String
    var suffix: String
    /// Text-offset hint from the JS walk at save time; re-anchoring tries
    /// this position first before falling back to prefix+quote+suffix search.
    var startOffset: Int
    var colorRaw: String
    var note: String = ""
    var createdAt: Date = Date()

    var color: HighlightColor {
        HighlightColor(rawValue: colorRaw) ?? .yellow
    }

    init(
        id: UUID = UUID(),
        epubFilename: String,
        chapterIndex: Int,
        chapterPath: String,
        quote: String,
        prefix: String,
        suffix: String,
        startOffset: Int,
        colorRaw: String,
        note: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.epubFilename = epubFilename
        self.chapterIndex = chapterIndex
        self.chapterPath = chapterPath
        self.quote = quote
        self.prefix = prefix
        self.suffix = suffix
        self.startOffset = startOffset
        self.colorRaw = colorRaw
        self.note = note
        self.createdAt = createdAt
    }
}

// MARK: - Store

@MainActor
@Observable
final class EPUBHighlightStore {

    private(set) var highlights: [EPUBHighlight] = []

    private let fileURL: URL

    init(fileURL customFileURL: URL? = nil) {
        if let customFileURL {
            self.fileURL = customFileURL
            self.highlights = Self.load(from: customFileURL)
            return
        }

        guard let dir = FileManager.default.rellAppSupportDirectory() else {
            self.fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("epub_highlights.json")
            self.highlights = []
            return
        }

        self.fileURL = dir.appendingPathComponent("epub_highlights.json")
        self.highlights = Self.load(from: fileURL)
    }

    // MARK: Queries

    func highlights(for filename: String) -> [EPUBHighlight] {
        highlights
            .filter { $0.epubFilename == filename }
            .sorted { lhs, rhs in
                lhs.chapterIndex == rhs.chapterIndex
                    ? lhs.createdAt > rhs.createdAt
                    : lhs.chapterIndex < rhs.chapterIndex
            }
    }

    /// Highlights for one chapter of one book — what the renderer needs
    /// after a chapter loads.
    func highlights(for filename: String, chapterPath: String) -> [EPUBHighlight] {
        highlights.filter { $0.epubFilename == filename && $0.chapterPath == chapterPath }
    }

    func count(for filename: String?) -> Int {
        guard let filename else { return 0 }
        return highlights.filter { $0.epubFilename == filename }.count
    }

    // MARK: Mutations

    func add(_ highlight: EPUBHighlight) {
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

    func updateNote(id: UUID, note: String) {
        guard let index = highlights.firstIndex(where: { $0.id == id }) else { return }
        highlights[index].note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        save()
        // Notes don't change the rendered mark, only the sidebar row.
    }

    /// Lets the EPUB reader re-render marks regardless of SwiftUI
    /// observation, which doesn't reliably reach a WKWebView.
    private func notifyChange() {
        NotificationCenter.default.post(name: .epubHighlightsChanged, object: nil)
    }

    // MARK: Persistence

    private func save() {
        do {
            try RELLJSONStore.save(highlights, to: fileURL, storeName: "EPUBHighlightStore")
        } catch {
            AppLogger.persistence.error("EPUBHighlightStore save failed at \(self.fileURL.path, privacy: .private): \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func load(from url: URL) -> [EPUBHighlight] {
        RELLJSONStore.load([EPUBHighlight].self, from: url, storeName: "EPUBHighlightStore", defaultValue: [])
    }
}

extension Notification.Name {
    static let epubHighlightsChanged = Notification.Name("epubHighlightsChanged")
}

// MARK: - Web Rendering

extension HighlightColor {
    /// Translucent CSS background for the `<mark>` the EPUB renderer
    /// inserts — legible over both light and themed (sepia/dark) pages,
    /// paired with dark ink text like a physical highlighter.
    var webBackground: String {
        switch self {
        case .yellow: return "rgba(255, 214, 0, 0.55)"
        case .green:  return "rgba(52, 199, 89, 0.45)"
        case .blue:   return "rgba(10, 132, 255, 0.40)"
        case .pink:   return "rgba(255, 55, 95, 0.40)"
        case .purple: return "rgba(191, 90, 242, 0.40)"
        }
    }
}
