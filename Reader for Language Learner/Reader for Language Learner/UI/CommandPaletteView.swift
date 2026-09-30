//
//  CommandPaletteView.swift
//  Reader for Language Learner
//
//  ⌘K (Roadmap v13 Sprint 5): type to find a command, a chapter, a page, a
//  saved word or a book; ↑/↓ to move, Return to run, Esc to close.
//

import SwiftUI

struct CommandPaletteView: View {
    let items: [PaletteItem]
    /// Builds a "go to page N" item for a numeric query, or nil.
    var pageItem: (Int) -> PaletteItem? = { _ in nil }

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var fieldFocused: Bool

    private var results: [PaletteItem] {
        var ranked = PaletteMatcher.rank(items, query: query, title: \.title, kind: \.kind.rawValue)
        if let page = PaletteMatcher.pageNumber(in: query), let item = pageItem(page) {
            ranked.insert(item, at: 0)
        }
        return ranked
    }

    var body: some View {
        let results = self.results
        VStack(spacing: 0) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(DS.Typography.icon(15))
                    .foregroundStyle(DS.Color.textTertiary)
                TextField("Search commands, chapters, words, books…", text: $query)
                    .textFieldStyle(.plain)
                    .font(DS.Typography.body)
                    .focused($fieldFocused)
                    .onSubmit { run(results) }
                    .onKeyPress(.downArrow) {
                        selection = min(selection + 1, max(0, results.count - 1)); return .handled
                    }
                    .onKeyPress(.upArrow) {
                        selection = max(selection - 1, 0); return .handled
                    }
                    .onKeyPress(.escape) { dismiss(); return .handled }
            }
            .padding(DS.Spacing.md)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                            row(item, selected: index == selection)
                                .id(index)
                                .contentShape(Rectangle())
                                .onTapGesture { selection = index; run(results) }
                        }
                        if results.isEmpty {
                            Text("No matches")
                                .font(DS.Typography.callout)
                                .foregroundStyle(DS.Color.textTertiary)
                                .padding(DS.Spacing.lg)
                        }
                    }
                    .padding(DS.Spacing.xs)
                }
                .onChange(of: selection) { _, index in proxy.scrollTo(index) }
            }
            .frame(height: 340)
        }
        .frame(width: 560)
        .onAppear { fieldFocused = true }
        .onChange(of: query) { _, _ in selection = 0 }
    }

    private func row(_ item: PaletteItem, selected: Bool) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: item.icon)
                .font(DS.Typography.icon(13))
                .foregroundStyle(selected ? DS.Color.accent : DS.Color.textSecondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(DS.Typography.callout)
                    .foregroundStyle(item.isEnabled ? DS.Color.textPrimary : DS.Color.textTertiary)
                    .lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(item.kind.localizedTitle)
                .font(DS.Typography.caption2)
                .foregroundStyle(DS.Color.textTertiary)
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xs)
        .background(selected ? DS.Color.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: DS.Radius.sm))
    }

    private func run(_ results: [PaletteItem]) {
        guard results.indices.contains(selection), results[selection].isEnabled else { return }
        let item = results[selection]
        dismiss()
        // After the sheet is gone, so a command that opens its own sheet
        // (import, story) isn't blocked by this one.
        DispatchQueue.main.async { item.perform() }
    }
}

extension PaletteItem.Kind {
    var localizedTitle: String {
        switch self {
        case .command:  return String(localized: "Command")
        case .page:     return String(localized: "Page")
        case .chapter:  return String(localized: "Chapter")
        case .word:     return String(localized: "Word")
        case .document: return String(localized: "Book")
        }
    }
}
