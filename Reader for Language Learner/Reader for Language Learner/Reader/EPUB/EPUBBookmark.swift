//
//  EPUBBookmark.swift
//  Reader for Language Learner
//
//  Model + store for reading-position bookmarks inside EPUBs. Unlike
//  highlights (text-quote anchored — there is a selection to anchor to),
//  a bookmark marks *where the reader is*: chapter index + scroll fraction,
//  the same position model the reading-position persistence and
//  `EPUBViewManager.openChapter(at:scrollTo:)` already use. The fraction
//  drifts if the text reflows (font size change), so the first visible
//  line of text is captured at creation time as `snippet` — today it's
//  the row label, later it can re-anchor without a schema migration.
//

import Foundation
import Observation
import os

// MARK: - Model

struct EPUBBookmark: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var epubFilename: String
    var chapterIndex: Int
    /// 0…1 scroll progress within the chapter at creation time.
    var scrollFraction: Double
    /// First visible line of text when the bookmark was created — the row
    /// label, and a future re-anchoring hook. May be empty if JS capture failed.
    var snippet: String
    var note: String = ""
    var createdAt: Date = Date()
}

// MARK: - Store

@MainActor
@Observable
final class EPUBBookmarkStore {

    private(set) var bookmarks: [EPUBBookmark] = []

    private let fileURL: URL

    /// Two positions within this fraction of a chapter count as "the same
    /// place" for toggle semantics — roughly one viewport of a long chapter.
    static let toggleTolerance = 0.02

    init(fileURL customFileURL: URL? = nil) {
        if let customFileURL {
            self.fileURL = customFileURL
            self.bookmarks = Self.load(from: customFileURL)
            return
        }

        guard let dir = FileManager.default.rellAppSupportDirectory() else {
            self.fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("epub_bookmarks.json")
            self.bookmarks = []
            return
        }

        self.fileURL = dir.appendingPathComponent("epub_bookmarks.json")
        self.bookmarks = Self.load(from: fileURL)
    }

    // MARK: Queries

    func bookmarks(for filename: String) -> [EPUBBookmark] {
        bookmarks
            .filter { $0.epubFilename == filename }
            .sorted { lhs, rhs in
                lhs.chapterIndex == rhs.chapterIndex
                    ? lhs.scrollFraction < rhs.scrollFraction
                    : lhs.chapterIndex < rhs.chapterIndex
            }
    }

    func count(for filename: String?) -> Int {
        guard let filename else { return 0 }
        return bookmarks.filter { $0.epubFilename == filename }.count
    }

    /// The bookmark at (approximately) this position, if any — same chapter
    /// and scroll fraction within `toggleTolerance`.
    func bookmark(for filename: String, chapterIndex: Int, near fraction: Double) -> EPUBBookmark? {
        bookmarks.first {
            $0.epubFilename == filename
                && $0.chapterIndex == chapterIndex
                && abs($0.scrollFraction - fraction) < Self.toggleTolerance
        }
    }

    func isBookmarked(filename: String, chapterIndex: Int, near fraction: Double) -> Bool {
        bookmark(for: filename, chapterIndex: chapterIndex, near: fraction) != nil
    }

    // MARK: Mutations

    func add(_ bookmark: EPUBBookmark) {
        bookmarks.insert(bookmark, at: 0)
        save()
    }

    func remove(id: UUID) {
        bookmarks.removeAll { $0.id == id }
        save()
    }

    /// Removes the bookmark near this position if one exists; otherwise adds
    /// one. Returns true when a bookmark was added.
    @discardableResult
    func toggle(filename: String, chapterIndex: Int, fraction: Double, snippet: String) -> Bool {
        if let existing = bookmark(for: filename, chapterIndex: chapterIndex, near: fraction) {
            remove(id: existing.id)
            return false
        }
        add(EPUBBookmark(
            epubFilename: filename,
            chapterIndex: chapterIndex,
            scrollFraction: fraction,
            snippet: snippet
        ))
        return true
    }

    func updateNote(id: UUID, note: String) {
        guard let index = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        bookmarks[index].note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        save()
    }

    // MARK: Persistence

    private func save() {
        do {
            try RELLJSONStore.save(bookmarks, to: fileURL, storeName: "EPUBBookmarkStore")
        } catch {
            AppLogger.persistence.error("EPUBBookmarkStore save failed at \(self.fileURL.path, privacy: .private): \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func load(from url: URL) -> [EPUBBookmark] {
        RELLJSONStore.load([EPUBBookmark].self, from: url, storeName: "EPUBBookmarkStore", defaultValue: [])
    }
}
