//
//  SavedWordsListView.swift
//  Reader for Language Learner
//

import SwiftUI

// MARK: - SavedWordsListView

struct SavedWordsListView: View {
    var store: SavedWordsStore
    var currentDocumentName: String?

    @Environment(CEFREstimator.self) private var cefrEstimator

    @AppStorage("savedWordsSortOrder") private var sortRaw = SavedWordsSortOrder.dateDesc.rawValue
    @State private var searchText    = ""
    @FocusState private var searchFocused: Bool
    @State private var selectedFilter: SavedWordsFilter = .all
    @State private var selectedTag: String?
    @State private var selectedCEFR: CEFRLevel?
    @State private var selectedLanguage: Language?
    @State private var selectedWord: SavedWord?
    @State private var showBulkExport = false
    @State private var showClearConfirm = false

    // Multi-select mode for bulk deck assignment / deletion.
    @State private var isSelecting = false
    @State private var multiSelection: Set<UUID> = []
    @State private var showBulkDeleteConfirm = false
    @State private var showNewDeckPrompt = false
    @State private var newDeckName = ""

    private var sortOrder: SavedWordsSortOrder {
        SavedWordsSortOrder(rawValue: sortRaw) ?? .dateDesc
    }

    private var filteredWords: [SavedWord] {
        var result = store.words

        switch selectedFilter {
        case .all:
            break
        case .needsReview:
            result = result.filter { store.isDue($0) }
        case .new:
            result = result.filter { $0.reviewStatus == .new }
        case .mastered:
            result = result.filter { $0.masteryLevel == .mastered }
        case .thisPDF:
            if let doc = currentDocumentName {
                result = result.filter { $0.pdfFilename == doc }
            }
        }

        // Tag / deck filter
        if let tag = selectedTag {
            result = result.filter { $0.hasTag(tag) }
        }

        // CEFR level filter
        if let selectedCEFR {
            result = result.filter { $0.cefrLevel == selectedCEFR.rawValue }
        }

        // Language filter
        if let selectedLanguage {
            result = result.filter { $0.language == selectedLanguage.rawValue }
        }

        // Search
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.term.lowercased().contains(q)
                    || ($0.pdfFilename?.lowercased().contains(q) ?? false)
                    || $0.notes.lowercased().contains(q)
                    || $0.sentence.lowercased().contains(q)
                    || $0.tags.contains { $0.lowercased().contains(q) }
            }
        }

        // Sort
        switch sortOrder {
        case .dateDesc:  result.sort { $0.savedAt > $1.savedAt }
        case .dateAsc:   result.sort { $0.savedAt < $1.savedAt }
        case .alphaAsc:  result.sort { $0.term.localizedCaseInsensitiveCompare($1.term) == .orderedAscending }
        case .alphaDesc: result.sort { $0.term.localizedCaseInsensitiveCompare($1.term) == .orderedDescending }
        }
        return result
    }

    private var availableFilters: [SavedWordsFilter] {
        currentDocumentName == nil
            ? SavedWordsFilter.allCases.filter { $0 != .thisPDF }
            : SavedWordsFilter.allCases
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            SavedWordsFilterBar(
                store: store,
                availableFilters: availableFilters,
                shownCount: filteredWords.count,
                selectedFilter: $selectedFilter,
                sortOrder: Binding(
                    get: { sortOrder },
                    set: { sortRaw = $0.rawValue }
                ),
                selectedTag: $selectedTag,
                selectedCEFR: $selectedCEFR,
                selectedLanguage: $selectedLanguage
            )
            Divider()
            listContent
            Divider()
            bottomToolbar
        }
        .overlay(alignment: .bottom) {
            if let err = store.saveError {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("Save failed: \(err)")
                        .lineLimit(2)
                }
                .font(DS.Typography.caption)
                .foregroundStyle(.white)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm)
                .background(DS.Color.danger.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
                .padding(DS.Spacing.sm)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onTapGesture { withAnimation(DS.Animation.standard) { store.saveError = nil } }
            }
        }
        .animation(DS.Animation.standard, value: store.saveError)
        .onReceive(NotificationCenter.default.publisher(for: .revealSavedWordCommand)) { note in
            guard let id = note.object as? UUID,
                  let word = store.words.first(where: { $0.id == id })
            else { return }
            // Clear narrowing filters so the revealed card is in the list.
            searchText = ""
            selectedFilter = .all
            selectedTag = nil
            selectedWord = word
        }
        .sheet(item: $selectedWord) { word in
            SavedWordDetailSheet(word: word, store: store)
        }
        .sheet(isPresented: $showBulkExport) {
            BulkAnkiExportView(store: store)
        }
        .confirmationDialog(
            "Clear all \(store.words.count) saved words?",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) { store.deleteAll() }
        }
        .confirmationDialog(
            "Delete \(multiSelection.count) selected words?",
            isPresented: $showBulkDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                store.delete(ids: multiSelection)
                multiSelection = []
                isSelecting = false
            }
        }
        .alert("New Deck", isPresented: $showNewDeckPrompt) {
            TextField("Deck name", text: $newDeckName)
            Button("Add") {
                store.addTag(newDeckName, toWordsWithIDs: multiSelection)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The deck will be added to all \(multiSelection.count) selected words.")
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        ZStack {
            searchShortcutButton
            DSSearchField(
                text: $searchText,
                placeholder: "Search words, notes, sources…",
                focused: $searchFocused
            )
            .help("Search saved words (⇧⌘F)")
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.top, DS.Spacing.sm)
    }

    /// Invisible button that keeps ⇧⌘F focusing the search field regardless
    /// of what currently has focus — a plain `.keyboardShortcut` on
    /// `DSSearchField` itself would have no default action to trigger. Live
    /// only while the Words tab is actually rendered (SidebarView's tab
    /// switch instantiates just the selected case), so this can't steal ⌘F
    /// from the reader's in-document Find while another tab is showing.
    private var searchShortcutButton: some View {
        Button { searchFocused = true } label: { Color.clear }
            .frame(width: 0, height: 0)
            .opacity(0)
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .accessibilityHidden(true)
    }

    // MARK: - List Content

    @ViewBuilder
    private var listContent: some View {
        if filteredWords.isEmpty {
            emptyState
        } else {
            List {
                ForEach(filteredWords) { word in
                    HStack(spacing: DS.Spacing.sm) {
                        if isSelecting {
                            Image(systemName: multiSelection.contains(word.id)
                                  ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(multiSelection.contains(word.id)
                                                 ? DS.Color.accent : DS.Color.textTertiary)
                        }
                        SavedWordRow(word: word)
                    }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if isSelecting {
                                if multiSelection.contains(word.id) {
                                    multiSelection.remove(word.id)
                                } else {
                                    multiSelection.insert(word.id)
                                }
                            } else {
                                selectedWord = word
                            }
                        }
                        .contextMenu {
                            Button("Edit Notes…") { selectedWord = word }
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(word.term, forType: .string)
                            } label: {
                                Label("Copy Term", systemImage: "doc.on.doc")
                            }
                            Divider()
                            Menu("Mark as…") {
                                ForEach(MasteryLevel.allCases, id: \.rawValue) { level in
                                    Button {
                                        store.setMastery(level, for: word)
                                    } label: {
                                        Label(level.localizedTitle, systemImage: level.icon)
                                    }
                                    .disabled(word.masteryLevel == level)
                                }
                            }
                            Menu("CEFR Level") {
                                ForEach(CEFRLevel.allCases) { level in
                                    Button {
                                        store.setCEFRLevel(level, for: word)
                                    } label: {
                                        Label(level.rawValue, systemImage: word.cefrLevel == level.rawValue ? "checkmark" : "")
                                    }
                                }
                                if word.cefrLevel != nil {
                                    Divider()
                                    Button("Clear Level") { store.setCEFRLevel(nil, for: word) }
                                }
                            }
                            Menu("Deck") {
                                ForEach(store.allTags, id: \.self) { tag in
                                    Button {
                                        if word.hasTag(tag) {
                                            store.removeTag(tag, from: word.id)
                                        } else {
                                            store.addTag(tag, to: word.id)
                                        }
                                    } label: {
                                        Label(tag, systemImage: word.hasTag(tag) ? "checkmark" : "")
                                    }
                                }
                                if !store.allTags.isEmpty { Divider() }
                                Button("Edit Tags…") { selectedWord = word }
                            }
                            Divider()
                            Button("Delete", role: .destructive) { store.delete(word) }
                        }
                }
                .onDelete { offsets in
                    offsets.map { filteredWords[$0] }.forEach { store.delete($0) }
                }
            }
            .listStyle(.plain)
            .animation(DS.Animation.standard, value: filteredWords.count)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        DSEmptyState(
            icon: searchText.isEmpty && selectedFilter == .all ? "star" : "magnifyingglass",
            title: emptyStateTitle,
            message: emptyStateMessage
        )
    }

    private var emptyStateTitle: LocalizedStringKey {
        searchText.isEmpty && selectedFilter == .all ? "No saved words yet" : "No results"
    }

    private var emptyStateMessage: LocalizedStringKey? {
        if searchText.isEmpty && selectedFilter == .all {
            return "Save vocabulary from the reader, then review due words here."
        }
        if selectedFilter == .thisPDF {
            return "No vocabulary saved from this document yet. Select text and save it from the inspector."
        }
        if selectedFilter == .needsReview {
            return "Nothing is due right now. Keep reading or include all saved words in Review."
        }
        if !searchText.isEmpty {
            return "Try a different search term."
        }
        return nil
    }

    // MARK: - Bottom Toolbar

    @ViewBuilder
    private var bottomToolbar: some View {
        if isSelecting {
            selectionToolbar
        } else {
            defaultToolbar
        }
    }

    private var defaultToolbar: some View {
        HStack(spacing: DS.Spacing.sm) {
            Button {
                showBulkExport = true
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
                    .font(DS.Typography.caption)
            }
            .disabled(store.words.isEmpty)

            Button {
                isSelecting = true
                multiSelection = []
            } label: {
                Label("Select", systemImage: "checkmark.circle")
                    .font(DS.Typography.caption)
            }
            .disabled(store.words.isEmpty)
            .help("Select multiple words for bulk deck assignment or deletion")

            Spacer()

            if !store.words.isEmpty {
                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.danger.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Clear all saved words")
            }
        }
        .controlSize(.small)
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.sm)
    }

    private var selectionToolbar: some View {
        HStack(spacing: DS.Spacing.sm) {
            Button("Done") {
                isSelecting = false
                multiSelection = []
            }
            .help("Exit selection mode")

            Text(String(localized: "\(multiSelection.count) selected"))
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.textTertiary)
                .lineLimit(1)

            Spacer(minLength: DS.Spacing.xs)

            Button {
                let visible = Set(filteredWords.map(\.id))
                multiSelection = multiSelection == visible ? [] : visible
            } label: {
                Image(systemName: "checklist.checked")
                    .font(DS.Typography.caption)
            }
            .buttonStyle(.plain)
            .help("Select or deselect all visible words")

            Menu {
                Section("Add to Deck") {
                    ForEach(store.allTags, id: \.self) { tag in
                        Button(tag) {
                            store.addTag(tag, toWordsWithIDs: multiSelection)
                        }
                    }
                    Button("New Deck…") {
                        newDeckName = ""
                        showNewDeckPrompt = true
                    }
                }
                if !tagsAcrossSelection.isEmpty {
                    Section("Remove from Deck") {
                        ForEach(tagsAcrossSelection, id: \.self) { tag in
                            Button(tag) {
                                store.removeTag(tag, fromWordsWithIDs: multiSelection)
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "tag")
                    .font(DS.Typography.caption)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 34)
            .disabled(multiSelection.isEmpty)
            .help("Assign or remove decks for the selected words")

            Menu {
                Menu("CEFR Level") {
                    ForEach(CEFRLevel.allCases) { level in
                        Button(level.rawValue) {
                            store.setCEFR(level, forWordsWithIDs: multiSelection)
                        }
                    }
                    Divider()
                    Button("Clear Level") {
                        store.setCEFR(nil, forWordsWithIDs: multiSelection)
                    }
                }
                Menu("Mastery") {
                    ForEach(MasteryLevel.allCases, id: \.self) { level in
                        Button(level.localizedTitle) {
                            store.setMastery(level, forWordsWithIDs: multiSelection)
                        }
                    }
                }
                Menu("Language") {
                    ForEach(Language.allCases) { language in
                        Button("\(language.flag) \(language.nativeName)") {
                            store.setLanguage(language, forWordsWithIDs: multiSelection)
                        }
                    }
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(DS.Typography.caption)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 34)
            .disabled(multiSelection.isEmpty)
            .help("Assign CEFR level, mastery, or language to the selected words")

            Button(role: .destructive) {
                showBulkDeleteConfirm = true
            } label: {
                Image(systemName: "trash")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.danger.opacity(0.85))
            }
            .buttonStyle(.plain)
            .disabled(multiSelection.isEmpty)
            .help("Delete the selected words")
        }
        .controlSize(.small)
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.sm)
    }

    /// Every deck present on at least one selected word.
    private var tagsAcrossSelection: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for word in store.words where multiSelection.contains(word.id) {
            for tag in word.tags where seen.insert(tag.lowercased()).inserted {
                ordered.append(tag)
            }
        }
        return ordered.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
