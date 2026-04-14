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
}

enum SavedWordsFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case needsReview = "Needs Review"
    case new = "New"
    case mastered = "Mastered"
    case thisPDF = "This PDF"

    var id: String { rawValue }
}

// MARK: - SavedWordsListView

struct SavedWordsListView: View {
    var store: SavedWordsStore
    var currentDocumentName: String?

    @AppStorage("savedWordsSortOrder") private var sortRaw = SavedWordsSortOrder.dateDesc.rawValue
    @State private var searchText    = ""
    @State private var selectedFilter: SavedWordsFilter = .all
    @State private var selectedWord: SavedWord?
    @State private var showBulkExport = false
    @State private var showClearConfirm = false

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

        // Search
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.term.lowercased().contains(q)
                    || ($0.pdfFilename?.lowercased().contains(q) ?? false)
                    || $0.notes.lowercased().contains(q)
                    || $0.sentence.lowercased().contains(q)
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
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(DS.Color.textTertiary)

            TextField("Search words, notes, sources…", text: $searchText)
                .textFieldStyle(.plain)
                .font(DS.Typography.callout)

            if !searchText.isEmpty {
                Button {
                    withAnimation(DS.Animation.fast) { searchText = "" }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DS.Color.textTertiary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
        .background(DS.Color.surfaceInset)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.top, DS.Spacing.sm)
        .animation(DS.Animation.fast, value: searchText.isEmpty)
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: DS.Spacing.xs) {
            // Sort picker
            Picker("", selection: Binding(
                get: { selectedFilter },
                set: { selectedFilter = $0 }
            )) {
                ForEach(availableFilters) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .labelsHidden()
            .controlSize(.mini)
            .frame(width: 110)

            Picker("", selection: Binding(
                get: { sortOrder },
                set: { sortRaw = $0.rawValue }
            )) {
                ForEach(SavedWordsSortOrder.allCases) { o in
                    Text(o.rawValue).tag(o)
                }
            }
            .labelsHidden()
            .controlSize(.mini)
            .frame(width: 84)

            Spacer()

            // Count label
            Text(countLabel)
                .font(DS.Typography.caption2)
                .foregroundStyle(DS.Color.textTertiary)
                .animation(DS.Animation.standard, value: filteredWords.count)
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xs)
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
                    SavedWordRow(word: word)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedWord = word }
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
        VStack(spacing: DS.Spacing.md) {
            Spacer()
            Image(systemName: searchText.isEmpty && selectedFilter == .all ? "star" : "magnifyingglass")
                .font(.system(size: 28, weight: .ultraLight))
                .foregroundStyle(DS.Color.textTertiary)
            VStack(spacing: DS.Spacing.xs) {
                if searchText.isEmpty && selectedFilter == .all {
                    Text("No saved words yet")
                        .font(DS.Typography.subhead)
                        .foregroundStyle(DS.Color.textSecondary)
                    Text("Select text and press ⌘D\nwhile reading to save vocabulary.")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                } else {
                    Text("No results")
                        .font(DS.Typography.subhead)
                        .foregroundStyle(DS.Color.textSecondary)
                    if selectedFilter == .thisPDF {
                        Text("No saved words from this PDF.")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Color.textTertiary)
                    } else if selectedFilter == .needsReview {
                        Text("Nothing is due right now.")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Color.textTertiary)
                    } else if !searchText.isEmpty {
                        Text("Try a different search term.")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Color.textTertiary)
                    }
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Bottom Toolbar

    private var bottomToolbar: some View {
        HStack(spacing: DS.Spacing.sm) {
            Button {
                showBulkExport = true
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
                    .font(DS.Typography.caption)
            }
            .disabled(store.words.isEmpty)

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
                Text(word.term)
                    .font(DS.Typography.callout.weight(.medium))
                    .foregroundStyle(DS.Color.textPrimary)
                    .lineLimit(1)

                // Source + domain badge + date row
                HStack(spacing: DS.Spacing.xs) {
                    if let pdf = word.pdfFilename {
                        HStack(spacing: 3) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 9))
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
                        Text(domain.rawValue)
                            .font(DS.Typography.caption2.weight(.semibold))
                            .foregroundStyle(domain.badgeColor)
                            .padding(.horizontal, DS.Spacing.xs)
                            .padding(.vertical, 1)
                            .background(domain.badgeColor.opacity(0.12))
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
