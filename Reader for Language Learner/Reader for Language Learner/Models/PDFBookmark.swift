//
//  PDFBookmark.swift
//  Reader for Language Learner
//
//  Model + store for user-created PDF page bookmarks.
//

import Foundation
import Observation

// MARK: - Model

struct PDFBookmark: Identifiable, Codable, Hashable {
    var id:          UUID   = UUID()
    var pdfFilename: String
    var pageIndex:   Int          // 0-based PDFDocument index
    var pageLabel:   String       // e.g. "Page 12" or the PDF's own page label
    var note:        String       // optional user annotation, may be ""
    var createdAt:   Date  = Date()
}

// MARK: - Store

@Observable
final class PDFBookmarkStore {

    private(set) var bookmarks: [PDFBookmark] = []

    private let udKey = "rell_pdf_bookmarks_v1"

    init() { load() }

    // MARK: Queries

    func bookmarks(for filename: String) -> [PDFBookmark] {
        bookmarks
            .filter { $0.pdfFilename == filename }
            .sorted { $0.pageIndex < $1.pageIndex }
    }

    func isBookmarked(filename: String, pageIndex: Int) -> Bool {
        bookmarks.contains { $0.pdfFilename == filename && $0.pageIndex == pageIndex }
    }

    // MARK: Mutations

    /// Adds a bookmark, ignoring duplicates for the same page.
    func add(_ bookmark: PDFBookmark) {
        guard !isBookmarked(filename: bookmark.pdfFilename, pageIndex: bookmark.pageIndex)
        else { return }
        bookmarks.insert(bookmark, at: 0)
        save()
    }

    func remove(id: UUID) {
        bookmarks.removeAll { $0.id == id }
        save()
    }

    func remove(filename: String, pageIndex: Int) {
        bookmarks.removeAll { $0.pdfFilename == filename && $0.pageIndex == pageIndex }
        save()
    }

    /// Adds the bookmark if the page is not yet bookmarked; removes it if it is.
    @discardableResult
    func toggle(filename: String, pageIndex: Int, pageLabel: String) -> Bool {
        if isBookmarked(filename: filename, pageIndex: pageIndex) {
            remove(filename: filename, pageIndex: pageIndex)
            return false
        } else {
            add(PDFBookmark(
                pdfFilename: filename,
                pageIndex:   pageIndex,
                pageLabel:   pageLabel,
                note:        ""
            ))
            return true
        }
    }

    func updateNote(id: UUID, note: String) {
        guard let idx = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        bookmarks[idx].note = note
        save()
    }

    // MARK: Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        UserDefaults.standard.set(data, forKey: udKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: udKey),
              let decoded = try? JSONDecoder().decode([PDFBookmark].self, from: data)
        else { return }
        bookmarks = decoded
    }
}
