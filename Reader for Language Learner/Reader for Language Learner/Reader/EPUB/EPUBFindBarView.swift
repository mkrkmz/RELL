//
//  EPUBFindBarView.swift
//  Reader for Language Learner
//
//  In-book search bar: next/previous highlight in the current chapter via
//  WebKit find, plus a per-chapter results list for jumping across the book.
//  Mirrors FindBarView's look and shortcuts.
//

import SwiftUI

struct EPUBFindBarView: View {
    var searchManager: EPUBSearchManager
    var epubManager: EPUBViewManager
    let onClose: () -> Void

    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchRow

            if searchManager.hasSearched, !searchManager.results.isEmpty {
                Divider()
                resultsList
            }
        }
        .background(DS.Color.surfaceElevated.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.sm)
                .strokeBorder(DS.Color.separator.opacity(0.30), lineWidth: 0.6)
        )
    }

    private var searchRow: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "magnifyingglass").foregroundStyle(DS.Color.textSecondary)

            TextField("Find in book…", text: Binding(
                get: { searchManager.query },
                set: { searchManager.query = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .focused($isFieldFocused)
            .onSubmit { runSearch() }
            .onAppear { isFieldFocused = true }

            Button { epubManager.findInPage(searchManager.query, forward: false) } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(searchManager.query.isEmpty)
            .keyboardShortcut(.return, modifiers: [.shift])
            .help("Previous Match (⇧↩)")

            Button { epubManager.findInPage(searchManager.query) } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(searchManager.query.isEmpty)
            .keyboardShortcut("g", modifiers: [.command])
            .help("Next Match (⌘G)")

            Text(matchLabel)
                .font(DS.Typography.mono)
                .foregroundStyle(DS.Color.textSecondary)
                .frame(minWidth: 70)

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(DS.Color.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Close Find (Esc)")
        }
        .padding(.horizontal, DS.Spacing.sm + DS.Spacing.xs)
        .padding(.vertical, DS.Spacing.sm)
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(searchManager.results) { result in
                    Button {
                        epubManager.openChapter(at: result.chapterIndex, thenFind: searchManager.query)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: DS.Spacing.xs) {
                                Text(result.chapterTitle)
                                    .font(DS.Typography.caption.weight(.medium))
                                    .foregroundStyle(
                                        result.chapterIndex == epubManager.chapterIndex
                                            ? DS.Color.accent : DS.Color.textPrimary
                                    )
                                    .lineLimit(1)
                                Spacer(minLength: DS.Spacing.xs)
                                Text("\(result.matchCount)")
                                    .font(DS.Typography.caption2)
                                    .foregroundStyle(DS.Color.textTertiary)
                            }
                            Text(result.snippet)
                                .font(DS.Typography.caption2)
                                .foregroundStyle(DS.Color.textTertiary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, DS.Spacing.xs)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxHeight: 180)
    }

    private var matchLabel: String {
        guard searchManager.hasSearched else { return "" }
        let total = searchManager.totalMatches
        return total == 0
            ? String(localized: "No matches")
            : String(localized: "\(total) matches")
    }

    private func runSearch() {
        guard let document = epubManager.document else { return }
        searchManager.runSearch(in: document)
        if searchManager.totalMatches > 0 {
            epubManager.findInPage(searchManager.query)
        }
    }
}
