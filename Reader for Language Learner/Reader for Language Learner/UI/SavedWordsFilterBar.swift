//
//  SavedWordsFilterBar.swift
//  Reader for Language Learner
//
//  The saved-words list's filter, sort, tag, level and language controls,
//  plus the count they narrow to. Split out of `SavedWordsListView`
//  (v10 Sprint 4, T3): the list view owns the selection state and passes it
//  down, so this file is only the controls.
//

import SwiftUI

struct SavedWordsFilterBar: View {
    var store: SavedWordsStore
    /// Filters offered — the list view decides whether "This Document"
    /// belongs in the roster.
    var availableFilters: [SavedWordsFilter]
    /// How many words the list is showing right now.
    var shownCount: Int

    @Binding var selectedFilter: SavedWordsFilter
    @Binding var sortOrder: SavedWordsSortOrder
    @Binding var selectedTag: String?
    @Binding var selectedCEFR: CEFRLevel?
    @Binding var selectedLanguage: Language?

    @Environment(CEFREstimator.self) private var cefrEstimator

    /// v14 S3: status, sort and one Filter menu (deck, level, language) on
    /// the first line; the count and the filters in effect — each removable
    /// — on the second. Before, up to five controls competed for one row
    /// and wrapped. Pickers have flexible frames so the row compresses with
    /// the sidebar instead of forcing it wider.
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            HStack(spacing: DS.Spacing.xs) {
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
                .frame(minWidth: 60, maxWidth: 120)

                Picker("", selection: Binding(
                    get: { sortOrder },
                    set: { sortOrder = $0 }
                )) {
                    ForEach(SavedWordsSortOrder.allCases) { o in
                        Text(o.localizedTitle).tag(o)
                    }
                }
                .labelsHidden()
                .controlSize(.mini)
                .frame(minWidth: 50, maxWidth: 90)

                filterMenu

                Spacer(minLength: 0)
            }

            HStack(spacing: DS.Spacing.xs) {
                countText
                activeFilterChips
                Spacer(minLength: 0)
            }
            .frame(height: 16)
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xs)
    }

    private var activeCount: Int {
        (selectedTag != nil ? 1 : 0) + (selectedCEFR != nil ? 1 : 0) + (selectedLanguage != nil ? 1 : 0)
    }

    // MARK: Filter menu

    private var filterMenu: some View {
        Menu {
            if !store.allTags.isEmpty {
                Section("Deck") {
                    Button {
                        selectedTag = nil
                    } label: {
                        Label("All decks", systemImage: selectedTag == nil ? "checkmark" : "")
                    }
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
                }
            }

            if !usedCEFRLevels.isEmpty || cefrEstimator.unratedCount > 0 {
                Section("Level") {
                    if !usedCEFRLevels.isEmpty {
                        Button {
                            selectedCEFR = nil
                        } label: {
                            Label("All levels", systemImage: selectedCEFR == nil ? "checkmark" : "")
                        }
                        ForEach(usedCEFRLevels) { level in
                            Button {
                                selectedCEFR = level
                            } label: {
                                Label(level.rawValue, systemImage: selectedCEFR == level ? "checkmark" : "")
                            }
                        }
                    }
                    if cefrEstimator.isRunningBulk {
                        Text("Estimating… \(cefrEstimator.bulkCompleted)/\(cefrEstimator.bulkTotal)")
                        Button("Cancel Estimation") { cefrEstimator.cancelBulk() }
                    } else if cefrEstimator.unratedCount > 0 {
                        Button {
                            cefrEstimator.estimateMissing()
                        } label: {
                            Label("Estimate Missing Levels (\(cefrEstimator.unratedCount))", systemImage: "sparkle")
                        }
                    }
                }
            }

            if usedLanguages.count > 1 {
                Section("Language") {
                    Button {
                        selectedLanguage = nil
                    } label: {
                        Label("All languages", systemImage: selectedLanguage == nil ? "checkmark" : "")
                    }
                    ForEach(usedLanguages) { language in
                        Button {
                            selectedLanguage = language
                        } label: {
                            Label("\(language.flag) \(language.nativeName)", systemImage: selectedLanguage == language ? "checkmark" : "")
                        }
                    }
                }
            }

            if activeCount > 0 {
                Divider()
                Button("Clear Filters") {
                    selectedTag = nil; selectedCEFR = nil; selectedLanguage = nil
                }
            }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "line.3.horizontal.decrease")
                Text(activeCount > 0 ? String(localized: "Filter (\(activeCount))") : String(localized: "Filter"))
                    .lineLimit(1)
            }
        }
        .menuStyle(.borderlessButton)
        .controlSize(.mini)
        .fixedSize()
        .help("Filter by deck, level or language")
    }

    // MARK: Active filters

    private var activeFilterChips: some View {
        HStack(spacing: DS.Spacing.xxs) {
            if let selectedTag {
                removableChip(selectedTag) { self.selectedTag = nil }
            }
            if let selectedCEFR {
                removableChip(selectedCEFR.rawValue) { self.selectedCEFR = nil }
            }
            if let selectedLanguage {
                removableChip("\(selectedLanguage.flag) \(selectedLanguage.shortCode)") { self.selectedLanguage = nil }
            }
        }
    }

    private func removableChip(_ title: String, remove: @escaping () -> Void) -> some View {
        Button(action: remove) {
            HStack(spacing: 2) {
                Text(title).lineLimit(1)
                Image(systemName: "xmark")
                    .font(DS.Typography.icon(7, weight: .bold))
            }
            .font(DS.Typography.caption2.weight(.medium))
            .foregroundStyle(DS.Color.accent)
            .padding(.horizontal, DS.Spacing.xs)
            .padding(.vertical, 1)
            .background(DS.Color.accentSubtle, in: Capsule())
        }
        .buttonStyle(.plain)
        .help(Text("Remove this filter"))
        .accessibilityLabel(Text("Remove filter \(title)"))
    }

    private var usedCEFRLevels: [CEFRLevel] {
        let present = Set(store.words.compactMap { $0.cefrLevel.flatMap(CEFRLevel.init) })
        return CEFRLevel.allCases.filter { present.contains($0) }
    }

    private var usedLanguages: [Language] {
        let present = Set(store.words.compactMap { $0.language.flatMap(Language.init) })
        return Language.allCases.filter { present.contains($0) }
    }

    private var countText: some View {
        Text(countLabel)
            .font(DS.Typography.caption2)
            .foregroundStyle(DS.Color.textTertiary)
            .lineLimit(1)
            .animation(DS.Animation.standard, value: shownCount)
    }

    private var countLabel: String {
        let total = store.words.count
        let shown = shownCount
        if selectedFilter == .all {
            return String(localized: "\(store.pendingReviewCount) due · \(total) saved")
        }
        if shown == total { return String(localized: "\(total) saved") }
        return String(localized: "\(shown) of \(total)")
    }
}
