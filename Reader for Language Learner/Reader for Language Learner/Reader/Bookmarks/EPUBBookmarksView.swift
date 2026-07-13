//
//  EPUBBookmarksView.swift
//  Reader for Language Learner
//
//  Sidebar panel listing bookmarks for the open book. Tap a row → jump to
//  that chapter and scroll position. Swipe left → delete. Pencil → edit note.
//  Mirrors PDFBookmarksView; the EPUB counterpart because the position model
//  (chapter + scroll fraction vs. page index) differs.
//

import SwiftUI

struct EPUBBookmarksView: View {

    var bookmarkStore:   EPUBBookmarkStore
    var epubManager:     EPUBViewManager
    var currentFilename: String?

    @State private var editingBookmark: EPUBBookmark?

    var body: some View {
        Group {
            if let filename = currentFilename {
                let entries = bookmarkStore.bookmarks(for: filename)
                if entries.isEmpty {
                    emptyState
                } else {
                    list(entries: entries)
                }
            } else {
                noDocumentState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $editingBookmark) { bookmark in
            EPUBBookmarkNoteSheet(bookmark: bookmark, store: bookmarkStore, chapterTitle: chapterTitle(for: bookmark))
        }
    }

    // MARK: - List

    private func list(entries: [EPUBBookmark]) -> some View {
        List {
            ForEach(entries) { bookmark in
                EPUBBookmarkRow(
                    bookmark: bookmark,
                    chapterTitle: chapterTitle(for: bookmark),
                    onEdit: { editingBookmark = bookmark }
                )
                .contentShape(Rectangle())
                .onTapGesture { navigate(to: bookmark) }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        withAnimation { bookmarkStore.remove(id: bookmark.id) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button { editingBookmark = bookmark } label: {
                        Label("Edit Note", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(
                    top: DS.Spacing.xxs, leading: DS.Spacing.sm,
                    bottom: DS.Spacing.xxs, trailing: DS.Spacing.sm
                ))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Navigation

    private func navigate(to bookmark: EPUBBookmark) {
        epubManager.openChapter(at: bookmark.chapterIndex, scrollTo: bookmark.scrollFraction)
    }

    private func chapterTitle(for bookmark: EPUBBookmark) -> String {
        let title = epubManager.document?.chapterTitle(at: bookmark.chapterIndex) ?? ""
        return title.isEmpty ? String(localized: "Chapter \(bookmark.chapterIndex + 1)") : title
    }

    // MARK: - Empty / No-doc States

    private var emptyState: some View {
        DSEmptyState(
            icon:    "bookmark",
            title:   "No Bookmarks",
            message: "Press ⌘B to bookmark your current position."
        )
    }

    private var noDocumentState: some View {
        DSEmptyState(
            icon:    "doc.text",
            title:   "No Document",
            message: "Open a book to start adding bookmarks."
        )
    }
}

// MARK: - EPUBBookmarkRow

private struct EPUBBookmarkRow: View {
    let bookmark: EPUBBookmark
    let chapterTitle: String
    var onEdit: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            // Chapter badge
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.xs)
                    .fill(DS.Color.accentSubtle)
                    .frame(width: 36, height: 36)
                Text("\(bookmark.chapterIndex + 1)")
                    .font(DS.Typography.label)
                    .foregroundStyle(DS.Color.accent)
            }

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(chapterTitle)
                    .font(DS.Typography.subhead)
                    .foregroundStyle(DS.Color.textPrimary)
                    .lineLimit(1)
                if !bookmark.snippet.isEmpty {
                    Text(bookmark.snippet)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                        .lineLimit(2)
                }
                if !bookmark.note.isEmpty {
                    Text(bookmark.note)
                        .font(DS.Typography.caption.italic())
                        .foregroundStyle(DS.Color.textSecondary)
                        .lineLimit(2)
                } else if isHovered, bookmark.snippet.isEmpty {
                    Text("Add note…")
                        .font(DS.Typography.caption.italic())
                        .foregroundStyle(DS.Color.textTertiary)
                }
                Text(bookmark.createdAt, style: .date)
                    .font(DS.Typography.caption2)
                    .foregroundStyle(DS.Color.textTertiary)
            }

            Spacer()

            if isHovered {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(DS.Typography.icon(11, weight: .medium))
                        .foregroundStyle(DS.Color.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(DS.Color.surfaceInset)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xs))
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale))
            } else {
                Image(systemName: "chevron.right")
                    .font(DS.Typography.icon(10, weight: .medium))
                    .foregroundStyle(DS.Color.textTertiary)
            }
        }
        .padding(DS.Spacing.sm)
        .background(DS.Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        .onHover { isHovered = $0 }
        .animation(DS.Animation.fast, value: isHovered)
    }
}

// MARK: - EPUBBookmarkNoteSheet

private struct EPUBBookmarkNoteSheet: View {
    @State var bookmark: EPUBBookmark
    var store: EPUBBookmarkStore
    let chapterTitle: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "bookmark.fill")
                    .foregroundStyle(DS.Color.accent)
                Text(chapterTitle)
                    .font(DS.Typography.headline)
                    .foregroundStyle(DS.Color.textPrimary)
                    .lineLimit(1)
                Spacer()
                Button("", systemImage: "xmark.circle.fill") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(DS.Color.textTertiary)
            }
            .padding(DS.Spacing.lg)

            Divider()

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text("NOTE")
                    .dsOverlineLabel()
                TextEditor(text: $bookmark.note)
                    .font(DS.Typography.callout)
                    .frame(minHeight: 80, maxHeight: 140)
                    .scrollContentBackground(.hidden)
                    .padding(DS.Spacing.sm)
                    .background(DS.Color.surfaceInset)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
            }
            .padding(DS.Spacing.lg)

            Spacer()

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    store.updateNote(id: bookmark.id, note: bookmark.note)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(DS.Spacing.lg)
        }
        .frame(width: 320, height: 270)
    }
}
