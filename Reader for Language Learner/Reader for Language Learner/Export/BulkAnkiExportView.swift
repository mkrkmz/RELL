//
//  BulkAnkiExportView.swift
//  Reader for Language Learner
//
//  Created by Codex on 15.02.2026.
//

import SwiftUI

struct BulkAnkiExportView: View {
    var store: SavedWordsStore
    @Environment(AnkiModulePreferences.self) private var prefs
    @Environment(\.dismiss) private var dismiss

    // Selection
    @State private var selectedIDs: Set<UUID> = []
    @State private var selectAll = true

    @State private var exportResult: ExportResult?

    private enum ExportResult {
        case success(Int)
        case cancelled
    }

    // Initialize selection to all words
    init(store: SavedWordsStore) {
        self.store = store
        _selectedIDs = State(initialValue: Set(store.words.map(\.id)))
    }

    var body: some View {
        @Bindable var prefs = prefs
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(.tint)
                Text("Bulk Export to Anki")
                    .font(.headline)
                Spacer()
                Text("\(selectedIDs.count) of \(store.words.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Select All toggle
                    Toggle("Select All", isOn: $selectAll)
                        .toggleStyle(.checkbox)
                        .font(.subheadline.weight(.medium))
                        .onChange(of: selectAll) { _, newValue in
                            if newValue {
                                selectedIDs = Set(store.words.map(\.id))
                            } else {
                                selectedIDs.removeAll()
                            }
                        }

                    // Word checklist
                    VStack(spacing: 2) {
                        ForEach(store.words) { word in
                            wordCheckRow(word)
                        }
                    }

                    Divider()

                    // Module selection
                    moduleSection

                    Divider()

                    // Tags
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tags")
                            .font(.subheadline.weight(.medium))
                        TextField("e.g. rell vocabulary", text: $prefs.tags)
                            .textFieldStyle(.roundedBorder)
                            .font(.callout)
                    }

                    // Source toggle
                    Toggle(isOn: $prefs.includeSource) {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text")
                                .foregroundStyle(.secondary)
                            Text("Include Source (PDF + page)")
                                .font(.subheadline)
                        }
                    }
                    .toggleStyle(.checkbox)

                    // Preview
                    if let firstSelected = store.words.first(where: { selectedIDs.contains($0.id) }) {
                        Divider()
                        previewSection(for: firstSelected)
                    }
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                if let result = exportResult {
                    switch result {
                    case .success(let count):
                        Label("\(count) cards exported!", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    case .cancelled:
                        Label("Cancelled", systemImage: "xmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save TSV") {
                    Task { await exportTSV() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedIDs.isEmpty)
            }
            .padding()
        }
        .frame(width: 420, height: 660)
    }

    // MARK: - Word Check Row

    private func wordCheckRow(_ word: SavedWord) -> some View {
        let isSelected = selectedIDs.contains(word.id)
        return HStack(spacing: 8) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            Text(word.term)
                .font(.callout)
                .lineLimit(1)
            Spacer()
            if let pdf = word.pdfFilename {
                Text(pdf)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected {
                selectedIDs.remove(word.id)
                if selectedIDs.count != store.words.count {
                    selectAll = false
                }
            } else {
                selectedIDs.insert(word.id)
                if selectedIDs.count == store.words.count {
                    selectAll = true
                }
            }
        }
    }

    // MARK: - Module Selection

    private var selectedModuleTypes: Set<ModuleType> {
        Set(ModuleType.allCases.filter { prefs.isIncluded($0) })
    }

    private var moduleSection: some View {
        @Bindable var prefs = prefs
        return VStack(alignment: .leading, spacing: 8) {
            Text("Back fields (LLM outputs)")
                .font(.subheadline.weight(.medium))
            ForEach(ModuleType.allCases) { module in
                moduleToggle(module, isOn: prefs.binding(for: module))
            }
        }
    }

    private func moduleToggle(_ module: ModuleType, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 6) {
                Image(systemName: module.iconName)
                    .frame(width: 16)
                Text(module.title)
                    .font(.callout)
            }
        }
        .toggleStyle(.checkbox)
    }

    // MARK: - Preview

    private func previewSection(for word: SavedWord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Preview (first card)")
                .font(.subheadline.weight(.medium))

            let note = buildNote(from: word)

            VStack(alignment: .leading, spacing: 4) {
                Text("Front: ").font(.caption.weight(.semibold)) + Text(note.front).font(.caption)
                Text("Back: ").font(.caption.weight(.semibold)) +
                    Text(note.back.isEmpty ? "(no LLM data)" : String(note.back.prefix(120)) + "…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !note.tags.isEmpty {
                    Text("Tags: ").font(.caption.weight(.semibold)) + Text(note.tags).font(.caption)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - Export Logic

    private func buildNote(from word: SavedWord) -> AnkiNoteDraft {
        var moduleOutputs: [ModuleType: String] = [:]
        for (key, value) in word.llmOutputs {
            if let module = ModuleType(rawValue: key) {
                moduleOutputs[module] = value
            }
        }

        let mode   = ExplainMode(rawValue: word.mode)     ?? .word
        let domain = DomainPreference(rawValue: word.domain) ?? .general

        return AnkiExporter.buildNote(
            selectedText: word.term,
            mode: mode,
            domain: domain,
            selectedModules: selectedModuleTypes,
            outputs: moduleOutputs,
            includeSource: prefs.includeSource,
            pdfFilename: word.pdfFilename,
            pageNumber: word.pageNumber,
            contextSentence: word.sentence,
            tags: prefs.tags
        )
    }

    @MainActor
    private func exportTSV() async {
        let selectedWords = store.words.filter { selectedIDs.contains($0.id) }
        guard !selectedWords.isEmpty else { return }

        let notes = selectedWords.map { buildNote(from: $0) }
        let content = AnkiExporter.tsvDocument(from: notes)
        let saved = await AnkiExporter.saveTSV(content: content)

        withAnimation(.easeInOut(duration: 0.2)) {
            exportResult = saved ? .success(notes.count) : .cancelled
        }

        if saved {
            try? await Task.sleep(for: .seconds(0.8))
            dismiss()
        }
    }
}
