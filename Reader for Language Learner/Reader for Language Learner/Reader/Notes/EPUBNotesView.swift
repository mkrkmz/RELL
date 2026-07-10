//
//  EPUBNotesView.swift
//  Reader for Language Learner
//
//  Sidebar panel listing standalone notes for the open book. "New Note"
//  captures the current chapter + scroll position; tap a row → jump back
//  there. Mirrors PDFNotesView's role for the reflowable world (simpler:
//  no categories, no selection anchoring — that's a highlight note).
//

import SwiftUI

struct EPUBNotesView: View {

    var noteStore:       EPUBNoteStore
    var epubManager:     EPUBViewManager
    var currentFilename: String?

    @State private var editingNote: EPUBNote?
    @State private var isCreatingNote = false

    var body: some View {
        Group {
            if let filename = currentFilename {
                VStack(spacing: 0) {
                    newNoteBar
                    Divider()
                    let entries = noteStore.notes(for: filename)
                    if entries.isEmpty {
                        emptyState
                    } else {
                        list(entries: entries)
                    }
                }
            } else {
                noDocumentState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $editingNote) { note in
            EPUBNoteEditorSheet(
                chapterTitle: chapterTitle(for: note),
                initialText: note.text,
                onSave: { text in
                    if text.isEmpty {
                        noteStore.remove(id: note.id)
                    } else {
                        noteStore.updateText(id: note.id, text: text)
                    }
                }
            )
        }
        .sheet(isPresented: $isCreatingNote) {
            EPUBNoteEditorSheet(
                chapterTitle: currentChapterTitle,
                initialText: "",
                onSave: { text in
                    guard !text.isEmpty, let currentFilename else { return }
                    noteStore.add(EPUBNote(
                        epubFilename: currentFilename,
                        chapterIndex: epubManager.chapterIndex,
                        scrollFraction: epubManager.scrollFraction,
                        text: text
                    ))
                }
            )
        }
    }

    // MARK: - New Note

    private var newNoteBar: some View {
        HStack {
            Button {
                isCreatingNote = true
            } label: {
                Label("New Note", systemImage: "square.and.pencil")
                    .font(DS.Typography.caption)
            }
            .controlSize(.small)
            .help("Add a note at your current reading position")
            Spacer()
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xs)
    }

    // MARK: - List

    private func list(entries: [EPUBNote]) -> some View {
        List {
            ForEach(entries) { note in
                EPUBNoteRow(note: note, chapterTitle: chapterTitle(for: note))
                    .contentShape(Rectangle())
                    .onTapGesture { navigate(to: note) }
                    .contextMenu {
                        Button("Edit Note…") { editingNote = note }
                        Button("Delete", role: .destructive) {
                            withAnimation { noteStore.remove(id: note.id) }
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            withAnimation { noteStore.remove(id: note.id) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button { editingNote = note } label: {
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

    // MARK: - Navigation & Titles

    private func navigate(to note: EPUBNote) {
        epubManager.openChapter(at: note.chapterIndex, scrollTo: note.scrollFraction)
    }

    private func chapterTitle(for note: EPUBNote) -> String {
        let title = epubManager.document?.chapterTitle(at: note.chapterIndex) ?? ""
        return title.isEmpty ? String(localized: "Chapter \(note.chapterIndex + 1)") : title
    }

    private var currentChapterTitle: String {
        let index = epubManager.chapterIndex
        let title = epubManager.document?.chapterTitle(at: index) ?? ""
        return title.isEmpty ? String(localized: "Chapter \(index + 1)") : title
    }

    // MARK: - Empty / No-doc States

    private var emptyState: some View {
        DSEmptyState(
            icon:    "note.text",
            title:   String(localized: "No Notes"),
            message: String(localized: "Use New Note to capture a thought at your current position.")
        )
    }

    private var noDocumentState: some View {
        DSEmptyState(
            icon:    "doc.text",
            title:   String(localized: "No Document"),
            message: String(localized: "Open a book to start taking notes.")
        )
    }
}

// MARK: - EPUBNoteRow

private struct EPUBNoteRow: View {
    let note: EPUBNote
    let chapterTitle: String

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text(note.text)
                .font(DS.Typography.subhead)
                .foregroundStyle(DS.Color.textPrimary)
                .lineLimit(3)
            HStack(spacing: DS.Spacing.xs) {
                Text(chapterTitle)
                    .font(DS.Typography.caption2)
                    .foregroundStyle(DS.Color.textTertiary)
                    .lineLimit(1)
                Text("·")
                    .font(DS.Typography.caption2)
                    .foregroundStyle(DS.Color.textTertiary)
                Text(note.createdAt, style: .date)
                    .font(DS.Typography.caption2)
                    .foregroundStyle(DS.Color.textTertiary)
                Spacer()
                if isHovered {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DS.Color.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Spacing.sm)
        .background(DS.Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        .onHover { isHovered = $0 }
        .animation(DS.Animation.fast, value: isHovered)
    }
}

// MARK: - Editor Sheet

private struct EPUBNoteEditorSheet: View {
    let chapterTitle: String
    let initialText: String
    var onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(chapterTitle: String, initialText: String, onSave: @escaping (String) -> Void) {
        self.chapterTitle = chapterTitle
        self.initialText = initialText
        self.onSave = onSave
        _text = State(initialValue: initialText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text("Note")
                    .font(DS.Typography.headline)
                Text(chapterTitle)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
                    .lineLimit(1)
            }

            TextEditor(text: $text)
                .font(DS.Typography.body)
                .scrollContentBackground(.hidden)
                .padding(DS.Spacing.xs)
                .background(DS.Color.surfaceInset)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
                .frame(minHeight: 120)

            HStack {
                if !initialText.isEmpty {
                    Button("Delete Note", role: .destructive) {
                        onSave("")
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(text.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DS.Spacing.lg)
        .frame(width: 380)
    }
}
