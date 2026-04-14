//
//  PDFNotesView.swift
//  Reader for Language Learner
//

import PDFKit
import SwiftUI

struct PDFNotesView: View {
    var noteStore: PDFNoteStore
    var savedWordsStore: SavedWordsStore
    var pdfViewManager: PDFViewManager
    var currentFilename: String?

    @State private var searchText = ""
    @State private var filter: PDFNoteFilter = .all
    @State private var editingNote: PDFNote?

    var body: some View {
        Group {
            if let filename = currentFilename {
                let allEntries = noteStore.notes(for: filename)
                let entries = noteStore.filteredNotes(
                    for: filename,
                    searchText: searchText,
                    filter: filter
                )
                if allEntries.isEmpty {
                    emptyState(for: filename, isFiltered: false)
                } else {
                    VStack(spacing: 0) {
                        notesToolbar(for: filename)
                        Divider()
                        if entries.isEmpty {
                            emptyState(for: filename, isFiltered: true)
                        } else {
                            list(entries: entries)
                        }
                    }
                }
            } else {
                noDocumentState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $editingNote) { note in
            PDFNoteEditorSheet(
                note: note,
                savedWordsStore: savedWordsStore,
                onJumpToPage: { navigate(to: $0) },
                onSave: { noteStore.update($0) },
                onCancel: {}
            )
        }
    }

    private func notesToolbar(for filename: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(DS.Color.textTertiary)
                TextField("Search notes", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(DS.Typography.callout)
            }
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.sm)
            .background(DS.Color.surfaceInset)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))

            HStack(spacing: DS.Spacing.xs) {
                ForEach(PDFNoteFilter.allCases) { item in
                    filterChip(item, filename: filename)
                }
            }
        }
        .padding(DS.Spacing.sm)
    }

    private func filterChip(_ item: PDFNoteFilter, filename: String) -> some View {
        let isSelected = filter == item
        let count = item.category.map { noteStore.count(for: currentFilename, category: $0) }
            ?? noteStore.count(for: currentFilename)

        return Button {
            withAnimation(DS.Animation.fast) {
                filter = item
            }
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                Text(item.label)
                Text("\(count)")
                    .font(DS.Typography.caption2.weight(.bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(isSelected ? .white.opacity(0.18) : DS.Color.surfaceInset)
                    .clipShape(Capsule())
            }
            .font(DS.Typography.caption.weight(.semibold))
            .foregroundStyle(isSelected ? .white : DS.Color.textSecondary)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, 6)
            .background(isSelected ? DS.Color.accent : DS.Color.surfaceElevated)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("\(item.label) notes in \(filename)")
    }

    private func list(entries: [PDFNote]) -> some View {
        List {
            ForEach(entries) { note in
                PDFNoteRow(
                    note: note,
                    onEdit: { editingNote = note },
                    onJump: { navigate(to: note) },
                    onSaveWord: { saveWord(from: note, queueForReview: false) },
                    onQueueReview: { saveWord(from: note, queueForReview: true) }
                )
                    .contentShape(Rectangle())
                    .onTapGesture { navigate(to: note) }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            withAnimation { noteStore.remove(id: note.id) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button { editingNote = note } label: {
                            Label("Edit", systemImage: "pencil")
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

    private func saveWord(from note: PDFNote, queueForReview: Bool) {
        let pageNumber = note.pageIndex + 1
        let existing = savedWordsStore.words.first(where: {
            $0.term.caseInsensitiveCompare(note.selectedText) == .orderedSame
                && $0.pdfFilename == note.pdfFilename
                && $0.pageNumber == pageNumber
        })

        if var existing {
            if queueForReview {
                existing.masteryLevel = .learning
                existing.nextReviewAt = Date()
                savedWordsStore.update(existing)
            }
            return
        }

        let word = SavedWord(
            term: note.selectedText,
            sentence: note.contextSentence,
            pdfFilename: note.pdfFilename,
            pageNumber: pageNumber,
            mode: ExplainMode.word.rawValue,
            domain: DomainPreference.general.rawValue,
            notes: note.note,
            llmOutputs: [:],
            masteryLevel: queueForReview ? .learning : .new,
            nextReviewAt: queueForReview ? Date() : nil
        )
        savedWordsStore.add(word)
    }

    private func navigate(to note: PDFNote) {
        guard let doc = pdfViewManager.pdfView?.document,
              note.pageIndex < doc.pageCount,
              let page = doc.page(at: note.pageIndex)
        else { return }
        pdfViewManager.pdfView?.go(to: page)
    }

    private func emptyState(for filename: String, isFiltered: Bool) -> some View {
        DSEmptyState(
            icon: isFiltered ? "line.3.horizontal.decrease.circle" : "note.text",
            title: isFiltered ? "No Matching Notes" : "No Notes Yet",
            message: isFiltered
                ? "Try a different search or filter for \(filename)."
                : "Select text in the PDF and add a note from the context menu."
        )
    }

    private var noDocumentState: some View {
        DSEmptyState(
            icon: "doc.text",
            title: "No Document",
            message: "Open a PDF to start collecting notes."
        )
    }
}

private struct PDFNoteRow: View {
    let note: PDFNote
    var onEdit: () -> Void
    var onJump: () -> Void
    var onSaveWord: () -> Void
    var onQueueReview: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            RoundedRectangle(cornerRadius: DS.Radius.xs)
                .fill(categoryColor.opacity(0.18))
                .frame(width: 6, height: 42)

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                HStack {
                    Label(note.category.label, systemImage: note.category.icon)
                        .font(DS.Typography.caption.weight(.semibold))
                        .foregroundStyle(categoryColor)
                    Text(note.pageLabel)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                    Spacer()
                    Text(note.updatedAt, style: .relative)
                        .font(DS.Typography.caption2)
                        .foregroundStyle(DS.Color.textTertiary)
                }

                Text(note.selectedText)
                    .font(DS.Typography.callout.weight(.medium))
                    .foregroundStyle(DS.Color.textPrimary)
                    .lineLimit(2)

                if !note.note.isEmpty {
                    Text(note.note)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                        .lineLimit(3)
                } else {
                    Text(note.contextSentence.isEmpty ? "No note text yet" : note.contextSentence)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                        .lineLimit(2)
                        .italic()
                }
            }

            if isHovered {
                VStack(spacing: DS.Spacing.xs) {
                    rowAction(systemName: "arrow.up.right.square", action: onJump)
                    rowAction(systemName: "star", action: onSaveWord)
                    rowAction(systemName: "clock.badge.plus", action: onQueueReview)
                    rowAction(systemName: "pencil", action: onEdit)
                }
                .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(DS.Spacing.sm)
        .background(DS.Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        .onHover { isHovered = $0 }
        .animation(DS.Animation.fast, value: isHovered)
    }

    private var categoryColor: Color {
        switch note.category {
        case .vocabulary: return .blue
        case .insight: return .orange
        case .review: return .mint
        }
    }

    private func rowAction(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.Color.textSecondary)
                .frame(width: 26, height: 26)
                .background(DS.Color.surfaceInset)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xs))
        }
        .buttonStyle(.plain)
    }
}

struct PDFNoteEditorSheet: View {
    @State var note: PDFNote
    var savedWordsStore: SavedWordsStore
    var onJumpToPage: (PDFNote) -> Void
    var onSave: (PDFNote) -> Void
    var onCancel: () -> Void
    @Environment(\.dismiss) private var dismiss

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "note.text.badge.plus")
                    .foregroundStyle(DS.Color.accent)
                Text("Reading Note")
                    .font(DS.Typography.headline)
                    .foregroundStyle(DS.Color.textPrimary)
                Spacer()
                Button("", systemImage: "xmark.circle.fill") {
                    onCancel()
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(DS.Color.textTertiary)
            }
            .padding(DS.Spacing.lg)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text("SOURCE").dsOverlineLabel()
                        Text("\(note.pdfFilename) · \(note.pageLabel)")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Color.textSecondary)
                        Text(note.selectedText)
                            .font(DS.Typography.callout.weight(.medium))
                            .foregroundStyle(DS.Color.textPrimary)
                            .textSelection(.enabled)
                    }

                    if !note.contextSentence.isEmpty {
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            Text("CONTEXT").dsOverlineLabel()
                            Text(note.contextSentence)
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Color.textSecondary)
                                .italic()
                        }
                    }

                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text("CATEGORY").dsOverlineLabel()
                        Picker("Category", selection: $note.category) {
                            ForEach(PDFNoteCategory.allCases) { category in
                                Label(category.label, systemImage: category.icon)
                                    .tag(category)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text("NOTE").dsOverlineLabel()
                        TextEditor(text: $note.note)
                            .font(DS.Typography.callout)
                            .frame(minHeight: 120, maxHeight: 180)
                            .scrollContentBackground(.hidden)
                            .padding(DS.Spacing.sm)
                            .background(DS.Color.surfaceInset)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
                    }

                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        Text("ACTIONS").dsOverlineLabel()
                        HStack {
                            Button("Jump to Page") {
                                onJumpToPage(note)
                            }
                            Button("Save Word") {
                                saveWord(queueForReview: false)
                            }
                            Button("Queue Review") {
                                saveWord(queueForReview: true)
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    Text("Created \(Self.dateFormatter.string(from: note.createdAt))")
                        .font(DS.Typography.caption2)
                        .foregroundStyle(DS.Color.textTertiary)
                }
                .padding(DS.Spacing.lg)
            }

            Divider()

            HStack {
                Button("Cancel") {
                    onCancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    onSave(note)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(DS.Spacing.lg)
        }
        .frame(width: 420, height: 460)
    }

    private func saveWord(queueForReview: Bool) {
        let pageNumber = note.pageIndex + 1
        let existing = savedWordsStore.words.first(where: {
            $0.term.caseInsensitiveCompare(note.selectedText) == .orderedSame
                && $0.pdfFilename == note.pdfFilename
                && $0.pageNumber == pageNumber
        })

        if var existing {
            if queueForReview {
                existing.masteryLevel = .learning
                existing.nextReviewAt = Date()
                savedWordsStore.update(existing)
            }
            return
        }

        savedWordsStore.add(
            SavedWord(
                term: note.selectedText,
                sentence: note.contextSentence,
                pdfFilename: note.pdfFilename,
                pageNumber: pageNumber,
                mode: ExplainMode.word.rawValue,
                domain: DomainPreference.general.rawValue,
                notes: note.note,
                llmOutputs: [:],
                masteryLevel: queueForReview ? .learning : .new,
                nextReviewAt: queueForReview ? Date() : nil
            )
        )
    }
}
