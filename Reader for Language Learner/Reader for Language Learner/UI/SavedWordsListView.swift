//
//  SavedWordsListView.swift
//  Reader for Language Learner
//

import SwiftUI

// MARK: - Sort Order

enum SavedWordsSortOrder: String, CaseIterable, Identifiable {
    case dateDesc = "Newest"
    case dateAsc  = "Oldest"
    case alphaAsc = "A → Z"
    case alphaDesc = "Z → A"
    var id: String { rawValue }

    /// Raw values back `@AppStorage("savedWordsSortOrder")` — keep them
    /// stable and English; the picker displays this instead.
    var localizedTitle: String {
        switch self {
        case .dateDesc:  return String(localized: "Newest")
        case .dateAsc:   return String(localized: "Oldest")
        case .alphaAsc:  return String(localized: "A → Z")
        case .alphaDesc: return String(localized: "Z → A")
        }
    }
}

enum SavedWordsFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case needsReview = "Needs Review"
    case new = "New"
    case mastered = "Mastered"
    case thisPDF = "This Document"

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .all:         return String(localized: "All")
        case .needsReview: return String(localized: "Needs Review")
        case .new:         return String(localized: "New")
        case .mastered:    return String(localized: "Mastered")
        case .thisPDF:     return String(localized: "This Document")
        }
    }
}

// MARK: - SavedWordsListView

struct SavedWordsListView: View {
    var store: SavedWordsStore
    var currentDocumentName: String?

    @AppStorage("savedWordsSortOrder") private var sortRaw = SavedWordsSortOrder.dateDesc.rawValue
    @State private var searchText    = ""
    @FocusState private var searchFocused: Bool
    @State private var selectedFilter: SavedWordsFilter = .all
    @State private var selectedTag: String?
    @State private var selectedCEFR: CEFRLevel?
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
            filterBar
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

    // MARK: - Filter Bar

    /// Controls must compress with the sidebar: fixed picker widths used to
    /// force this row wider than the panel, clipping the whole list. Pickers
    /// now have flexible frames and the count wraps to its own line when the
    /// single-row layout doesn't fit.
    private var filterBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Spacing.xs) {
                filterControls
                Spacer(minLength: DS.Spacing.xs)
                countText
            }

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                HStack(spacing: DS.Spacing.xs) {
                    filterControls
                    Spacer(minLength: 0)
                }
                countText
            }
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xs)
    }

    @ViewBuilder
    private var filterControls: some View {
        Picker("", selection: Binding(
            get: { selectedFilter },
            set: { selectedFilter = $0 }
        )) {
            ForEach(availableFilters) { filter in
                Text(filter.localizedTitle).tag(filter)
            }
        }
        .labelsHidden()
        .controlSize(.mini)
        .frame(minWidth: 76, maxWidth: 120)

        Picker("", selection: Binding(
            get: { sortOrder },
            set: { sortRaw = $0.rawValue }
        )) {
            ForEach(SavedWordsSortOrder.allCases) { o in
                Text(o.localizedTitle).tag(o)
            }
        }
        .labelsHidden()
        .controlSize(.mini)
        .frame(minWidth: 60, maxWidth: 90)

        if !store.allTags.isEmpty {
            Menu {
                Button {
                    selectedTag = nil
                } label: {
                    Label("All decks", systemImage: selectedTag == nil ? "checkmark" : "")
                }
                Divider()
                ForEach(store.allTags, id: \.self) { tag in
                    Button {
                        selectedTag = tag
                    } label: {
                        Label(
                            "\(tag) (\(store.tagCount(tag)))",
                            systemImage: selectedTag?.lowercased() == tag.lowercased() ? "checkmark" : ""
                        )
                    }
                }
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "tag")
                    Text(selectedTag ?? "Deck")
                        .lineLimit(1)
                }
            }
            .menuStyle(.borderlessButton)
            .controlSize(.mini)
            .frame(maxWidth: 96)
            .help("Filter by deck (tag)")
        }

        if !usedCEFRLevels.isEmpty {
            Menu {
                Button {
                    selectedCEFR = nil
                } label: {
                    Label("All levels", systemImage: selectedCEFR == nil ? "checkmark" : "")
                }
                Divider()
                ForEach(usedCEFRLevels) { level in
                    Button {
                        selectedCEFR = level
                    } label: {
                        Label(level.rawValue, systemImage: selectedCEFR == level ? "checkmark" : "")
                    }
                }
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "graduationcap")
                    Text(selectedCEFR?.rawValue ?? "CEFR")
                        .lineLimit(1)
                }
            }
            .menuStyle(.borderlessButton)
            .controlSize(.mini)
            .frame(maxWidth: 80)
            .help("Filter by CEFR level")
        }
    }

    private var usedCEFRLevels: [CEFRLevel] {
        let present = Set(store.words.compactMap { $0.cefrLevel.flatMap(CEFRLevel.init) })
        return CEFRLevel.allCases.filter { present.contains($0) }
    }

    private var countText: some View {
        Text(countLabel)
            .font(DS.Typography.caption2)
            .foregroundStyle(DS.Color.textTertiary)
            .lineLimit(1)
            .animation(DS.Animation.standard, value: filteredWords.count)
    }

    private var countLabel: String {
        let total = store.words.count
        let shown = filteredWords.count
        if selectedFilter == .all {
            return "\(store.pendingReviewCount) due · \(total) saved"
        }
        if shown == total { return "\(total) saved" }
        return "\(shown) of \(total)"
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
                                        Label(level.label, systemImage: level.icon)
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

// MARK: - Row

private struct SavedWordRow: View {
    let word: SavedWord

    @State private var isHovered = false

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            // Mastery dot — color reflects learning progress
            Circle()
                .fill(word.masteryLevel.color.opacity(0.7))
                .frame(width: 6, height: 6)
                .padding(.top, 5)
                .help(word.masteryLevel.label)

            VStack(alignment: .leading, spacing: DS.Spacing.xxs + 1) {
                // Term
                HStack(spacing: DS.Spacing.xs) {
                    Text(word.term)
                        .font(DS.Typography.callout.weight(.medium))
                        .foregroundStyle(DS.Color.textPrimary)
                        .lineLimit(1)
                    if isHovered {
                        SpeakButton(text: word.term, size: 11)
                            .transition(.opacity)
                    }
                }

                // Source + domain badge + date row
                HStack(spacing: DS.Spacing.xs) {
                    if let pdf = word.pdfFilename {
                        HStack(spacing: 3) {
                            Image(systemName: "doc.text")
                                .font(DS.Typography.icon(9))
                            Text(pdf)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .foregroundStyle(DS.Color.textTertiary)
                        if let p = word.pageNumber {
                            Text("p.\(p)")
                                .foregroundStyle(DS.Color.textTertiary)
                        }
                    }

                    // Domain badge (hidden for General to reduce noise)
                    let domain = DomainPreference(rawValue: word.domain) ?? .general
                    if domain != .general {
                        Text(domain.localizedTitle)
                            .font(DS.Typography.caption2.weight(.semibold))
                            .foregroundStyle(domain.badgeColor)
                            .padding(.horizontal, DS.Spacing.xs)
                            .padding(.vertical, 1)
                            .background(domain.badgeColor.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    if let cefr = word.cefrLevel.flatMap(CEFRLevel.init) {
                        Text(cefr.rawValue)
                            .font(DS.Typography.caption2.weight(.semibold))
                            .foregroundStyle(cefr.badgeColor)
                            .padding(.horizontal, DS.Spacing.xs)
                            .padding(.vertical, 1)
                            .background(cefr.badgeColor.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    Spacer()

                    // Mode indicator
                    let mode = ExplainMode(rawValue: word.mode) ?? .word
                    Image(systemName: mode == .word ? "character.cursor.ibeam" : "text.alignleft")
                        .foregroundStyle(DS.Color.textTertiary)

                    Text(Self.relativeFormatter.localizedString(for: word.savedAt, relativeTo: Date()))
                        .foregroundStyle(DS.Color.textTertiary)
                }
                .font(DS.Typography.caption2)

                HStack(spacing: DS.Spacing.xs) {
                    Label(word.reviewStatus.label, systemImage: word.reviewStatus.icon)
                        .font(DS.Typography.caption2.weight(.semibold))
                        .foregroundStyle(word.reviewStatus.color)

                    if let nextReviewAt = word.nextReviewAt, word.reviewStatus != .mastered {
                        Text("Next \(Self.relativeFormatter.localizedString(for: nextReviewAt, relativeTo: Date()))")
                            .font(DS.Typography.caption2)
                            .foregroundStyle(DS.Color.textTertiary)
                    }
                }

                // Tag chips
                if !word.tags.isEmpty {
                    FlowLayout(spacing: 3) {
                        ForEach(word.tags, id: \.self) { tag in
                            TagChip(tag: tag)
                        }
                    }
                    .padding(.top, 1)
                }

                // Notes snippet
                if !word.notes.isEmpty {
                    Text(word.notes)
                        .font(DS.Typography.caption2)
                        .foregroundStyle(DS.Color.textSecondary)
                        .lineLimit(1)
                        .italic()
                }

                // Module output dots — colored indicator per saved module
                let savedModules = ModuleType.allCases.filter {
                    !(word.llmOutputs[$0.rawValue] ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                if !savedModules.isEmpty {
                    HStack(spacing: DS.Spacing.xs) {
                        ForEach(savedModules) { module in
                            Circle()
                                .fill(module.accentColor.opacity(0.75))
                                .frame(width: 5, height: 5)
                        }
                    }
                    .padding(.top, 1)
                }

                // Definition snippet (from saved LLM output)
                if let defn = word.llmOutputs[ModuleType.definitionEN.rawValue]?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !defn.isEmpty {
                    Text(defn)
                        .font(DS.Typography.caption2)
                        .foregroundStyle(DS.Color.textTertiary)
                        .lineLimit(2)
                        .padding(.top, 1)
                }
            }
        }
        .padding(.vertical, DS.Spacing.xxs)
        .background(isHovered ? DS.Color.hoverOverlay : .clear)
        .onHover { isHovered = $0 }
        .animation(DS.Animation.fast, value: isHovered)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(word.term), \(word.masteryLevel.label)")
        .accessibilityHint("Tap to view details")
        .accessibilityValue(word.pdfFilename.map { "from \($0)" } ?? "")
    }
}

// MARK: - Detail Sheet

private struct SavedWordDetailSheet: View {
    @State var word: SavedWord
    var store: SavedWordsStore
    @Environment(\.dismiss) private var dismiss

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                Text(word.term)
                    .font(DS.Typography.headline)
                    .foregroundStyle(DS.Color.textPrimary)
                Spacer()
                Button("", systemImage: "xmark.circle.fill") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(DS.Color.textTertiary)
            }
            .padding(DS.Spacing.lg)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    metadataSection

                    Divider()

                    // Tags editor
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text("TAGS / DECKS").dsOverlineLabel()
                        TagEditorView(tags: $word.tags, suggestions: store.allTags)
                    }

                    Divider()

                    // Notes editor
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text("NOTES").dsOverlineLabel()
                        TextEditor(text: $word.notes)
                            .font(DS.Typography.callout)
                            .frame(minHeight: 64, maxHeight: 120)
                            .scrollContentBackground(.hidden)
                            .padding(DS.Spacing.sm)
                            .background(DS.Color.surfaceInset)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
                    }

                    // LLM output cards
                    if !word.llmOutputs.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                            Text("SAVED OUTPUTS").dsOverlineLabel()
                            ForEach(ModuleType.allCases.filter { word.llmOutputs[$0.rawValue] != nil }) { module in
                                let value = word.llmOutputs[module.rawValue] ?? ""
                                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                                    HStack(spacing: DS.Spacing.xs) {
                                        Circle()
                                            .fill(module.accentColor)
                                            .frame(width: 5, height: 5)
                                        Text(module.title)
                                            .font(DS.Typography.caption.weight(.semibold))
                                            .foregroundStyle(DS.Color.textSecondary)
                                    }
                                    Text(value.trimmingCharacters(in: .whitespacesAndNewlines))
                                        .font(DS.Typography.caption)
                                        .foregroundStyle(DS.Color.textPrimary)
                                        .textSelection(.enabled)
                                }
                                .padding(DS.Spacing.sm)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(DS.Color.surfaceInset)
                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
                            }
                        }
                    }
                }
                .padding(DS.Spacing.lg)
            }

            Divider()

            // Footer
            HStack {
                Button("Delete", role: .destructive) {
                    store.delete(word); dismiss()
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { store.update(word); dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(DS.Spacing.lg)
        }
        .frame(width: 420, height: 540)
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text("METADATA").dsOverlineLabel()

            if let pdf = word.pdfFilename {
                metaRow("Source", value: pdf + (word.pageNumber.map { " · p.\($0)" } ?? ""))
            }
            metaRow("Mode",   value: word.mode)
            metaRow("Domain", value: word.domain)
            metaRow("Saved",  value: Self.dateFormatter.string(from: word.savedAt))
            metaRow("Status", value: word.reviewStatus.label)
            metaRow("Reviews", value: "\(word.reviewCount)")
            metaRow("Incorrect", value: "\(word.incorrectCount)")
            if let lastReviewedAt = word.lastReviewedAt {
                metaRow("Reviewed", value: Self.dateFormatter.string(from: lastReviewedAt))
            }
            if let nextReviewAt = word.nextReviewAt {
                metaRow("Next", value: Self.dateFormatter.string(from: nextReviewAt))
            }

            if !word.sentence.isEmpty {
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text("Context")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                    Text(word.sentence)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textPrimary)
                        .textSelection(.enabled)
                        .italic()
                }
            }
        }
    }

    private func metaRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            Text(label)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.textTertiary)
                .frame(width: 52, alignment: .trailing)
            Text(value)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.textPrimary)
                .textSelection(.enabled)
        }
    }
}
