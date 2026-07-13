//
//  HighlightsView.swift
//  Reader for Language Learner
//
//  Sidebar panel listing user-created highlights for the open document.
//  Tap a row → jump to that page. Swipe → delete. Swatch menu → recolor.
//

import PDFKit
import SwiftUI

struct HighlightsView: View {

    var highlightStore:  PDFHighlightStore
    var pdfViewManager:  PDFViewManager
    var currentFilename: String?

    @State private var noteTarget: PDFHighlight?

    var body: some View {
        Group {
            if let filename = currentFilename {
                let entries = highlightStore.highlights(for: filename)
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
        .sheet(item: $noteTarget) { highlight in
            HighlightNoteEditorSheet(
                highlight: highlight,
                onSave: { highlightStore.updateNote(id: highlight.id, note: $0) }
            )
        }
    }

    // MARK: - List

    private func list(entries: [PDFHighlight]) -> some View {
        List {
            ForEach(entries) { highlight in
                HighlightRow(
                    highlight: highlight,
                    onRecolor: { highlightStore.updateColor(id: highlight.id, color: $0) },
                    onEditNote: { noteTarget = highlight }
                )
                .contentShape(Rectangle())
                .onTapGesture { navigate(to: highlight) }
                .contextMenu {
                    Button(highlight.note.isEmpty ? "Add Note…" : "Edit Note…") {
                        noteTarget = highlight
                    }
                    Button("Delete", role: .destructive) {
                        withAnimation { highlightStore.remove(id: highlight.id) }
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        withAnimation { highlightStore.remove(id: highlight.id) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
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

    private func navigate(to highlight: PDFHighlight) {
        guard let doc = pdfViewManager.pdfView?.document,
              highlight.pageIndex < doc.pageCount,
              let page = doc.page(at: highlight.pageIndex)
        else { return }
        pdfViewManager.pdfView?.go(to: page)
    }

    // MARK: - Empty / No-doc States

    private var emptyState: some View {
        DSEmptyState(
            icon:    "highlighter",
            title:   "No Highlights",
            message: "Select text, right-click, and choose Highlight to mark passages."
        )
    }

    private var noDocumentState: some View {
        DSEmptyState(
            icon:    "doc.text",
            title:   "No Document",
            message: "Open a PDF to start highlighting."
        )
    }
}

// MARK: - HighlightRow

private struct HighlightRow: View {
    let highlight: PDFHighlight
    var onRecolor: (HighlightColor) -> Void
    var onEditNote: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            // Color spine
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(nsColor: highlight.color.nsColor))
                .frame(width: 4)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(highlight.selectedText)
                    .font(DS.Typography.subhead)
                    .foregroundStyle(DS.Color.textPrimary)
                    .lineLimit(2)
                HStack(spacing: DS.Spacing.xs) {
                    Text(highlight.pageLabel)
                        .font(DS.Typography.caption2)
                        .foregroundStyle(DS.Color.textTertiary)
                    Text("·")
                        .font(DS.Typography.caption2)
                        .foregroundStyle(DS.Color.textTertiary)
                    Text(highlight.createdAt, style: .date)
                        .font(DS.Typography.caption2)
                        .foregroundStyle(DS.Color.textTertiary)
                }
                if !highlight.note.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xxs) {
                        Image(systemName: "note.text")
                            .font(.system(size: 9))
                            .foregroundStyle(DS.Color.textTertiary)
                        Text(highlight.note)
                            .font(DS.Typography.caption2)
                            .foregroundStyle(DS.Color.textSecondary)
                            .italic()
                            .lineLimit(2)
                    }
                }
            }

            Spacer(minLength: DS.Spacing.xs)

            if isHovered {
                HStack(spacing: DS.Spacing.xs) {
                    Button(action: onEditNote) {
                        Image(systemName: highlight.note.isEmpty ? "note.text.badge.plus" : "note.text")
                            .font(.system(size: 11))
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help(highlight.note.isEmpty ? "Add a note" : "Edit note")

                    recolorMenu
                }
                .transition(.opacity)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DS.Color.textTertiary)
            }
        }
        .padding(DS.Spacing.sm)
        .frame(minHeight: 44)
        .background(DS.Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        .onHover { isHovered = $0 }
        .animation(DS.Animation.fast, value: isHovered)
    }

    private var recolorMenu: some View {
        Menu {
            ForEach(HighlightColor.allCases) { color in
                Button {
                    onRecolor(color)
                } label: {
                    Label {
                        Text(color.label)
                    } icon: {
                        Image(systemName: highlight.color == color ? "checkmark.circle.fill" : "circle.fill")
                            .foregroundStyle(Color(nsColor: color.nsColor))
                    }
                }
            }
        } label: {
            Circle()
                .fill(Color(nsColor: highlight.color.nsColor))
                .frame(width: 14, height: 14)
                .overlay(Circle().strokeBorder(DS.Color.hairlineStrong, lineWidth: 0.5))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Change highlight color")
    }
}

// MARK: - Note Editor Sheet

private struct HighlightNoteEditorSheet: View {
    let highlight: PDFHighlight
    var onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(highlight: PDFHighlight, onSave: @escaping (String) -> Void) {
        self.highlight = highlight
        self.onSave = onSave
        _text = State(initialValue: highlight.note)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text("Note")
                    .font(DS.Typography.headline)
                Text("“\(String(highlight.selectedText.prefix(90)))”")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
                    .lineLimit(2)
            }

            TextEditor(text: $text)
                .font(DS.Typography.body)
                .scrollContentBackground(.hidden)
                .padding(DS.Spacing.xs)
                .background(DS.Color.surfaceInset)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
                .frame(minHeight: 120)

            HStack {
                if !highlight.note.isEmpty {
                    Button("Remove Note", role: .destructive) {
                        onSave("")
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(text)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DS.Spacing.lg)
        .frame(width: 380)
    }
}
