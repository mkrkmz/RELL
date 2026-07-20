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

    // Scope — narrows which words the checklist (and thus export) covers.
    @State private var scopeDeck: String?
    @State private var scopeCEFR: CEFRLevel?
    @State private var scopeMastery: MasteryLevel?
    @State private var scopeLanguage: Language?

    @AppStorage("bulkExportFormat") private var formatRaw = ExportFormat.ankiTSV.rawValue

    @State private var exportResult: ExportResult?

    private var format: ExportFormat {
        ExportFormat(rawValue: formatRaw) ?? .ankiTSV
    }

    private enum ExportResult {
        case success(Int)
        case cancelled
    }

    /// Words matching the current deck/CEFR/mastery/language scope. The
    /// checklist and `selectedIDs` always operate on this subset, not the
    /// whole store.
    private var scopedWords: [SavedWord] {
        store.words.filter { word in
            (scopeDeck == nil || word.hasTag(scopeDeck!))
                && (scopeCEFR == nil || word.cefrLevel == scopeCEFR!.rawValue)
                && (scopeMastery == nil || word.masteryLevel == scopeMastery!)
                && (scopeLanguage == nil || word.language == scopeLanguage!.rawValue)
        }
    }

    // Initialize selection to all words
    init(store: SavedWordsStore) {
        self.store = store
        _selectedIDs = State(initialValue: Set(store.words.map(\.id)))
    }

    /// Re-selects everything currently in scope. Called whenever a scope
    /// filter changes, so the checklist never shows a stale selection from
    /// outside the new scope.
    private func applyScope() {
        selectedIDs = Set(scopedWords.map(\.id))
        selectAll = true
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
                Text("\(selectedIDs.count) of \(scopedWords.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Scope
                    scopeSection

                    Divider()

                    // Select All toggle
                    Toggle("Select All", isOn: $selectAll)
                        .toggleStyle(.checkbox)
                        .font(.subheadline.weight(.medium))
                        .onChange(of: selectAll) { _, newValue in
                            if newValue {
                                selectedIDs = Set(scopedWords.map(\.id))
                            } else {
                                selectedIDs.removeAll()
                            }
                        }

                    // Word checklist
                    VStack(spacing: 2) {
                        ForEach(scopedWords) { word in
                            wordCheckRow(word)
                        }
                    }

                    Divider()

                    // Export format
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Format")
                            .font(.subheadline.weight(.medium))
                        Picker("", selection: Binding(
                            get: { format },
                            set: { formatRaw = $0.rawValue }
                        )) {
                            ForEach(ExportFormat.allCases) { format in
                                // Format names are proper nouns — not localized.
                                Text(format.rawValue).tag(format)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        Text(format.localizedHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                            Text("Include Source (document + page/chapter)")
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
                            .foregroundStyle(DS.Color.success)
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

                Button("Export…") {
                    Task { await export() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedIDs.isEmpty)
            }
            .padding()
        }
        .frame(width: 420, height: 660)
    }

    // MARK: - Scope

    private var scopeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Scope")
                .font(.subheadline.weight(.medium))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                scopeMenu(
                    title: String(localized: "Deck"), systemImage: "tag",
                    currentLabel: scopeDeck ?? String(localized: "All decks")
                ) {
                    Button(String(localized: "All decks")) { scopeDeck = nil; applyScope() }
                    if !store.allTags.isEmpty {
                        Divider()
                        ForEach(store.allTags, id: \.self) { tag in
                            Button(tag) { scopeDeck = tag; applyScope() }
                        }
                    }
                }
                scopeMenu(
                    title: String(localized: "CEFR"), systemImage: "graduationcap",
                    currentLabel: scopeCEFR?.rawValue ?? String(localized: "All levels")
                ) {
                    Button(String(localized: "All levels")) { scopeCEFR = nil; applyScope() }
                    Divider()
                    ForEach(CEFRLevel.allCases) { level in
                        Button(level.rawValue) { scopeCEFR = level; applyScope() }
                    }
                }
                scopeMenu(
                    title: String(localized: "Mastery"), systemImage: "brain",
                    currentLabel: scopeMastery?.localizedTitle ?? String(localized: "All")
                ) {
                    Button(String(localized: "All")) { scopeMastery = nil; applyScope() }
                    Divider()
                    ForEach(MasteryLevel.allCases, id: \.self) { level in
                        Button(level.localizedTitle) { scopeMastery = level; applyScope() }
                    }
                }
                scopeMenu(
                    title: String(localized: "Language"), systemImage: "globe",
                    currentLabel: scopeLanguage?.nativeName ?? String(localized: "All languages")
                ) {
                    Button(String(localized: "All languages")) { scopeLanguage = nil; applyScope() }
                    Divider()
                    ForEach(Language.allCases) { language in
                        Button("\(language.flag) \(language.nativeName)") { scopeLanguage = language; applyScope() }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func scopeMenu<Content: View>(
        title: String, systemImage: String, currentLabel: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                Text(currentLabel)
                    .lineLimit(1)
            }
            .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .help(title)
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
                if selectedIDs.count != scopedWords.count {
                    selectAll = false
                }
            } else {
                selectedIDs.insert(word.id)
                if selectedIDs.count == scopedWords.count {
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
            tags: prefs.tags,
            extraTags: word.tags
        )
    }

    @MainActor
    private func export() async {
        let selectedWords = store.words.filter { selectedIDs.contains($0.id) }
        guard !selectedWords.isEmpty else { return }

        let notes = selectedWords.map { buildNote(from: $0) }
        let content = AnkiExporter.document(from: notes, format: format)
        let saved = await AnkiExporter.save(content: content, format: format)

        withAnimation(.easeInOut(duration: 0.2)) {
            exportResult = saved ? .success(notes.count) : .cancelled
        }

        if saved {
            try? await Task.sleep(for: .seconds(0.8))
            dismiss()
        }
    }
}
