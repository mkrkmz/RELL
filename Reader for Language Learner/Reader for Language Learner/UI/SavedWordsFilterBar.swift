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

    /// Controls must compress with the sidebar: fixed picker widths used to
    /// force this row wider than the panel, clipping the whole list. Pickers
    /// now have flexible frames and the count wraps to its own line when the
    /// single-row layout doesn't fit.
    var body: some View {
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
            set: { sortOrder = $0 }
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

        if !usedCEFRLevels.isEmpty || cefrEstimator.unratedCount > 0 {
            Menu {
                if !usedCEFRLevels.isEmpty {
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
                    Divider()
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

        if usedLanguages.count > 1 {
            Menu {
                Button {
                    selectedLanguage = nil
                } label: {
                    Label("All languages", systemImage: selectedLanguage == nil ? "checkmark" : "")
                }
                Divider()
                ForEach(usedLanguages) { language in
                    Button {
                        selectedLanguage = language
                    } label: {
                        Label("\(language.flag) \(language.nativeName)", systemImage: selectedLanguage == language ? "checkmark" : "")
                    }
                }
            } label: {
                HStack(spacing: 2) {
                    Text(selectedLanguage?.flag ?? "🌐")
                    Text(selectedLanguage?.shortCode ?? String(localized: "Language"))
                        .lineLimit(1)
                }
            }
            .menuStyle(.borderlessButton)
            .controlSize(.mini)
            .frame(maxWidth: 88)
            .help("Filter by language")
        }
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
            return "\(store.pendingReviewCount) due · \(total) saved"
        }
        if shown == total { return "\(total) saved" }
        return "\(shown) of \(total)"
    }
}
