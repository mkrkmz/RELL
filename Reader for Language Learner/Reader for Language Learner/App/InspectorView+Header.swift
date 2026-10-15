//
//  InspectorView+Header.swift
//  Reader for Language Learner
//
//  The selection card's shared parts: quick actions, recent terms, the
//  overflow menu (v14 S2).
//

import SwiftUI

extension InspectorView {

    // MARK: - Saved State

    var isCurrentlySaved: Bool {
        currentlySavedWord != nil
    }

    var currentlySavedWord: SavedWord? {
        savedWordsStore.words.first {
            $0.term.lowercased() == trimmedSelection.lowercased()
                && $0.pdfFilename == pdfFilename
                && $0.pageNumber == pageNumber
        }
    }

    // MARK: - Selection Header

    /// The top of the inspector (v14 S2): what is selected and what you can
    /// do with it, in one card. A word gets the word card; a phrase or
    /// sentence gets the sentence card, then its tools.
    @ViewBuilder
    var selectionHeader: some View {
        if isSingleWordSelection {
            wordCard
        } else {
            sentenceCard
        }
    }

    /// The selection is saved — the save button lives in the overflow menu
    /// for a phrase or sentence, so its state shows here.
    @ViewBuilder
    var savedBadge: some View {
        if let savedWord = currentlySavedWord {
            Label(savedWord.reviewStatus.label, systemImage: savedWord.reviewStatus.icon)
                .labelStyle(.iconOnly)
                .foregroundStyle(savedWord.reviewStatus.color)
                .help(Text("Saved · \(savedWord.reviewStatus.label)"))
                .accessibilityLabel("Word is saved to vocabulary. Review status: \(savedWord.reviewStatus.label)")
        }
    }

    // MARK: - Recent Terms (menu in the card's corner)

    @ViewBuilder
    var recentTermsMenu: some View {
        let recents = viewModel.recentTerms.filter {
            $0.lowercased() != trimmedSelection.lowercased()
        }.prefix(8)

        if !recents.isEmpty {
            Menu {
                Section("Recent") {
                    ForEach(Array(recents), id: \.self) { term in
                        Button(term) {
                            NotificationCenter.default.post(name: .inspectorRecentTermSelected, object: term)
                        }
                    }
                }
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(DS.Typography.icon(11, weight: .medium))
                    .foregroundStyle(DS.Color.textTertiary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Recent terms")
            .accessibilityLabel("Recent terms")
        }
    }

    var exportShortcutButton: some View {
        Button { showAnkiExport = true } label: { Color.clear }
            .frame(width: 0, height: 0)
            .opacity(0)
            .keyboardShortcut("e", modifiers: [.command])
            .disabled(!hasSelection)
            .accessibilityHidden(true)
    }

    var stopShortcutButton: some View {
        Button { speechManager.stop() } label: { Color.clear }
            .frame(width: 0, height: 0)
            .opacity(0)
            .keyboardShortcut("x", modifiers: [.command, .shift])
            .disabled(!speechManager.isSpeaking)
            .accessibilityHidden(true)
    }
}
