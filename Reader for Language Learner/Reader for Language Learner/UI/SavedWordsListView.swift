//
//  SavedWordsListView.swift
//  Reader for Language Learner
//

import SwiftUI

// MARK: - SavedWordsListView

struct SavedWordsListView: View {
    var store: SavedWordsStore
    var currentDocumentName: String?
    /// The open book: the list shows its words only (v16 S1). Nil shows
    /// every saved word.
    var book: BookContext? = nil
    var onStudyBook: (() -> Void)? = nil

    /// A book as its sidebar knows it.
    struct BookContext: Equatable {
        let document: BookIdentity.Document
        let title: String
    }

    @Environment(WordEnricher.self) private var enricher: WordEnricher?
    @AppStorage(StorageKey.fillUsesProvider) private var fillUsesProvider = true
    @Environment(WordEncounterStore.self) private var encounterStore: WordEncounterStore?

    @AppStorage(StorageKey.savedWordsSortOrder) private var sortRaw = SavedWordsSortOrder.dateDesc.rawValue
    @State private var searchText    = ""
    @FocusState private var searchFocused: Bool
    @State private var selectedFilter: SavedWordsFilter = .all
    @State private var selectedTag: String?
    @State private var selectedCEFR: CEFRLevel?
    @State private var selectedLanguage: Language?
    @State private var missingMeaningOnly = false
    @State private var showFillSheet = false
    /// The words "Fill Missing" works on: the selection, or nil for all.
    @State private var fillScope: Set<UUID>?
    @State private var selectedWord: SavedWord?
    @State private var showBulkExport = false
    @State private var showKindleImport = false
    @State private var showClearConfirm = false
    @State private var showAllMet = false
    /// Bumped when the book's merge switch changes, to recompute.
    @State private var matchingRevision = 0
    /// "Met again" shows this many before "Show all" (decision 2).
    private static let collapsedMetCount = 5

    // Multi-select mode for bulk deck assignment / deletion.
    @State private var isSelecting = false
    @State private var multiSelection: Set<UUID> = []
    @State private var showBulkDeleteConfirm = false
    @State private var showNewDeckPrompt = false
    @State private var newDeckName = ""

    private var sortOrder: SavedWordsSortOrder {
        SavedWordsSortOrder(rawValue: sortRaw) ?? .dateDesc
    }

    private var matchesTitles: Bool {
        _ = matchingRevision
        return BookWords.matchesTitles(forDocumentAt: book?.document.path)
    }

    private var bookWords: BookWords? {
        book.map { BookWords(document: $0.document, words: store.words,
                             encounters: encounterStore?.encounters ?? [], matchingTitles: matchesTitles) }
    }

    /// Met again in this book, narrowed by the search.
    private func metWords(_ bookWords: BookWords) -> [SavedWord] {
        guard !searchText.isEmpty else { return bookWords.met }
        let q = searchText.lowercased()
        return bookWords.met.filter { $0.term.lowercased().contains(q) }
    }

    private var filteredWords: [SavedWord] {
        var result = bookWords?.saved ?? store.words

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
            break  // v16 S1: the list itself is the book's now
        }

        // Tag / deck filter
        if let tag = selectedTag {
            result = result.filter { $0.hasTag(tag) }
        }

        // CEFR level filter
        if let selectedCEFR {
            result = result.filter { $0.cefrLevel == selectedCEFR.rawValue }
        }

        // Card filter (v15 S1)
        if missingMeaningOnly {
            result = result.filter { FillField.meaning.isMissing(in: $0) }
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
        SavedWordsFilter.allCases.filter { $0 != .thisPDF }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if let book { bookHeader(book) }
            searchBar
            SavedWordsFilterBar(
                store: store,
                scope: bookWords?.saved,
                availableFilters: availableFilters,
                shownCount: filteredWords.count,
                selectedFilter: $selectedFilter,
                sortOrder: Binding(
                    get: { sortOrder },
                    set: { sortRaw = $0.rawValue }
                ),
                selectedTag: $selectedTag,
                selectedCEFR: $selectedCEFR,
                selectedLanguage: $selectedLanguage,
                missingMeaningOnly: $missingMeaningOnly
            )
            if let enricher {
                FillMissingStrip(enricher: enricher, wordIDs: bookWords?.ids) {
                    fillScope = bookWords?.ids
                    showFillSheet = true
                }
            }
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
        .sheet(isPresented: $showFillSheet) {
            if let enricher {
                FillMissingSheet(store: store, enricher: enricher, wordIDs: fillScope) {
                    searchText = ""
                    selectedFilter = .all
                    missingMeaningOnly = true
                }
            }
        }
        .sheet(isPresented: $showKindleImport) {
            KindleImportSheet(store: store, enricher: enricher)
        }
        .sheet(isPresented: $showBulkExport) {
            BulkAnkiExportView(store: store, limitedTo: bookWords?.ids)
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
                placeholder: book == nil ? "Search words, notes, sources…" : "Search this book…",
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
        if let book, let bookWords {
            bookList(book, bookWords)
        } else if filteredWords.isEmpty {
            emptyState
        } else {
            let lastEncounters = encounterStore?.latestByWord() ?? [:]
            List {
                ForEach(filteredWords) { word in
                    wordRow(word, lastEncounters: lastEncounters)
                }
                .onDelete { offsets in
                    offsets.map { filteredWords[$0] }.forEach { store.delete($0) }
                }
            }
            .listStyle(.plain)
            .animation(DS.Animation.standard, value: filteredWords.count)
        }
    }

    // MARK: - Book (v16 S1)

    private func bookHeader(_ book: BookContext) -> some View {
        let words = bookWords?.saved ?? []
        let due = words.count { store.isDue($0) }
        return HStack(spacing: DS.Spacing.xs) {
            VStack(alignment: .leading, spacing: 0) {
                Text(book.title)
                    .font(DS.Typography.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(words.isEmpty ? String(localized: "No words yet")
                                   : String(localized: "\(words.count) words · \(due) waiting for review"))
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            bookMenu(book)
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.top, DS.Spacing.sm)
    }

    private func bookMenu(_ book: BookContext) -> some View {
        Menu {
            Toggle(isOn: Binding(
                get: { matchesTitles },
                set: { on in
                    if let path = book.document.path { BookWords.setMatchesTitles(on, forDocumentAt: path) }
                    matchingRevision += 1
                }
            )) {
                Text("Include Other Copies and Kindle")
            }
            if let sources = bookWords?.sources, !sources.isEmpty {
                Section("Words From") {
                    ForEach(sources) { source in
                        Text(sourceLabel(source))
                    }
                }
            }
            Divider()
            if let onStudyBook {
                Button("Study This Book Full Screen", action: onStudyBook)
            }
            Button("Export This Book's Words…") { showBulkExport = true }
                .disabled(bookWords?.saved.isEmpty ?? true)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("This book's words")
        .accessibilityLabel("This book's words")
    }

    private func sourceLabel(_ source: BookWords.Source) -> String {
        switch source.kind {
        case .thisFile:  return String(localized: "This file (\(source.count))")
        case .kindle:    return String(localized: "Kindle · \(source.name) (\(source.count))")
        case .otherCopy: return String(localized: "Another copy · \(source.name) (\(source.count))")
        }
    }

    @ViewBuilder
    private func bookList(_ book: BookContext, _ bookWords: BookWords) -> some View {
        let saved = filteredWords
        let met = metWords(bookWords)
        if saved.isEmpty && met.isEmpty {
            if bookWords.saved.isEmpty && bookWords.met.isEmpty {
                DSEmptyState(icon: "character.book.closed",
                             title: "No words from this book yet",
                             message: "Double-click a word while you read and choose Save.")
            } else {
                emptyState
            }
        } else {
            let lastEncounters = encounterStore?.latestByWord() ?? [:]
            List {
                if !saved.isEmpty {
                    Section {
                        ForEach(saved) { word in
                            wordRow(word, lastEncounters: lastEncounters)
                        }
                    } header: {
                        sectionHeader(String(localized: "SAVED FROM THIS BOOK"), count: saved.count)
                    }
                }
                if !met.isEmpty {
                    Section {
                        let shown = showAllMet ? met : Array(met.prefix(Self.collapsedMetCount))
                        ForEach(shown) { word in
                            wordRow(word, lastEncounters: lastEncounters)
                        }
                        if met.count > Self.collapsedMetCount {
                            Button(showAllMet ? String(localized: "Show fewer")
                                              : String(localized: "Show all \(met.count)")) {
                                withAnimation(DS.Animation.standard) { showAllMet.toggle() }
                            }
                            .buttonStyle(.link)
                            .font(DS.Typography.caption)
                        }
                    } header: {
                        sectionHeader(String(localized: "MET AGAIN IN THIS BOOK"), count: met.count)
                    }
                }
            }
            .listStyle(.plain)
            .animation(DS.Animation.standard, value: saved.count)
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title).dsOverlineLabel()
            Spacer()
            Text("\(count)")
                .font(DS.Typography.caption2)
                .foregroundStyle(DS.Color.textTertiary)
                .monospacedDigit()
        }
    }

    /// One word's row, with its context menu.
    @ViewBuilder
    private func wordRow(_ word: SavedWord, lastEncounters: [UUID: WordEncounter]) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            if isSelecting {
                Image(systemName: multiSelection.contains(word.id)
                      ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(multiSelection.contains(word.id)
                                     ? DS.Color.accent : DS.Color.textTertiary)
            }
            SavedWordRow(word: word, lastEncounter: lastEncounters[word.id])
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
                if let enricher, FillField.defaultSelection.contains(where: { $0.isMissing(in: word) }) {
                    Button {
                        Task { await enricher.fill(wordID: word.id, allowProvider: fillUsesProvider) }
                    } label: {
                        Label("Fill Missing", systemImage: "text.badge.plus")
                    }
                }
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

    // MARK: - Empty State

    /// Says why the list is empty and, when a search or filter is the
    /// reason, offers to undo it (v14 S3).
    @ViewBuilder
    private var emptyState: some View {
        if !searchText.isEmpty {
            DSEmptyState(icon: "magnifyingglass", title: emptyStateTitle, message: emptyStateMessage,
                         action: { searchText = "" }, actionLabel: "Clear Search")
        } else if selectedFilter != .all {
            DSEmptyState(icon: "line.3.horizontal.decrease.circle", title: emptyStateTitle, message: emptyStateMessage,
                         action: { selectedFilter = .all }, actionLabel: "Show All Words")
        } else {
            DSEmptyState(icon: "star", title: emptyStateTitle, message: emptyStateMessage)
        }
    }

    private var emptyStateTitle: LocalizedStringKey {
        searchText.isEmpty && selectedFilter == .all ? "No saved words yet" : "No results"
    }

    private var emptyStateMessage: LocalizedStringKey? {
        if searchText.isEmpty && selectedFilter == .all {
            return "While reading, double-click a word and choose Save. It shows up here, ready to review."
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
                showKindleImport = true
            } label: {
                Label("Import From Kindle", systemImage: "books.vertical")
                    .labelStyle(.iconOnly)
                    .font(DS.Typography.caption)
            }
            .help("Import the words you looked up on your Kindle")
            .accessibilityLabel("Import From Kindle")

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
                .accessibilityLabel("Clear all saved words")
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
            .accessibilityLabel("Select or deselect all visible words")

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
            .accessibilityLabel("Decks for the selected words")
            .menuStyle(.borderlessButton)
            .frame(width: 34)
            .disabled(multiSelection.isEmpty)
            .help("Assign or remove decks for the selected words")

            Menu {
                if enricher != nil {
                    Button("Fill Missing…") {
                        fillScope = multiSelection
                        showFillSheet = true
                    }
                    Divider()
                }
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
            .accessibilityLabel("Change level or language of the selected words")
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
            .accessibilityLabel("Delete the selected words")
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
