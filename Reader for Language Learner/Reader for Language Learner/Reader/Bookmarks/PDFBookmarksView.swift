//
//  PDFBookmarksView.swift
//  Reader for Language Learner
//
//  Sidebar panel listing user-created bookmarks for the open document.
//  Tap a row → jump to that page.  Swipe left → delete.  Pencil icon → edit note.
//

import PDFKit
import SwiftUI

struct PDFBookmarksView: View {

    var bookmarkStore:   PDFBookmarkStore
    var pdfViewManager:  PDFViewManager
    var currentFilename: String?      // nil when no document is open

    @State private var editingBookmark: PDFBookmark?

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
            BookmarkNoteSheet(bookmark: bookmark, store: bookmarkStore)
        }
    }

    // MARK: - List

    private func list(entries: [PDFBookmark]) -> some View {
        List {
            ForEach(entries) { bookmark in
                BookmarkRow(bookmark: bookmark, onEdit: { editingBookmark = bookmark })
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

    private func navigate(to bookmark: PDFBookmark) {
        guard let doc = pdfViewManager.pdfView?.document,
              bookmark.pageIndex < doc.pageCount,
              let page = doc.page(at: bookmark.pageIndex)
        else { return }
        pdfViewManager.pdfView?.go(to: page)
    }

    // MARK: - Empty / No-doc States

    private var emptyState: some View {
        DSEmptyState(
            icon:    "bookmark",
            title:   "No Bookmarks",
            message: "Press ⌘B to bookmark the current page."
        )
    }

    private var noDocumentState: some View {
        DSEmptyState(
            icon:    "doc.text",
            title:   "No Document",
            message: "Open a PDF to start adding bookmarks."
        )
    }
}

// MARK: - BookmarkRow

private struct BookmarkRow: View {
    let bookmark: PDFBookmark
    var onEdit: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            // Page badge
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.xs)
                    .fill(DS.Color.accentSubtle)
                    .frame(width: 36, height: 36)
                Text("\(bookmark.pageIndex + 1)")
                    .font(DS.Typography.label)
                    .foregroundStyle(DS.Color.accent)
            }

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(bookmark.pageLabel)
                    .font(DS.Typography.subhead)
                    .foregroundStyle(DS.Color.textPrimary)
                    .lineLimit(1)
                if !bookmark.note.isEmpty {
                    Text(bookmark.note)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                        .lineLimit(2)
                } else if isHovered {
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
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.Color.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(DS.Color.surfaceInset)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xs))
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale))
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
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

// MARK: - BookmarkNoteSheet

private struct BookmarkNoteSheet: View {
    @State var bookmark: PDFBookmark
    var store: PDFBookmarkStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Header ────────────────────────────────────────────────────
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "bookmark.fill")
                    .foregroundStyle(DS.Color.accent)
                Text(bookmark.pageLabel)
                    .font(DS.Typography.headline)
                    .foregroundStyle(DS.Color.textPrimary)
                Spacer()
                Button("", systemImage: "xmark.circle.fill") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(DS.Color.textTertiary)
            }
            .padding(DS.Spacing.lg)

            Divider()

            // ── Note editor ───────────────────────────────────────────────
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

            // ── Footer ────────────────────────────────────────────────────
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
