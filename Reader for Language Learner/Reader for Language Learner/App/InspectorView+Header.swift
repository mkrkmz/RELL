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

    // MARK: - Quick Actions (inside the card)

    /// Save, listen, Anki and the rest — labelled, inside the card. Before
    /// v14 S2 these were unlabelled icons in a row of their own.
    var quickActions: some View {
        HStack(spacing: DS.Spacing.xs) {
            if isSingleWordSelection {
                Button(action: toggleSaveWord) {
                    Label(isCurrentlySaved ? "Saved" : "Save", systemImage: isCurrentlySaved ? "star.fill" : "star")
                }
                .buttonStyle(.borderedProminent)
                .tint(isCurrentlySaved ? DS.Color.star : DS.Color.accent)
                .keyboardShortcut("d", modifiers: [.command])
                .help(isCurrentlySaved ? "Remove from saved vocabulary (⌘D)" : "Save to vocabulary (⌘D)")
            }

            Button {
                if speechManager.isSpeaking { speechManager.stop() } else { speakSelection() }
            } label: {
                Label(speechManager.isSpeaking ? "Stop" : "Listen",
                      systemImage: speechManager.isSpeaking ? "stop.fill" : "play.fill")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .help(speechManager.isSpeaking ? "Stop speaking (⇧⌘X)" : "Speak selected text (⇧⌘S)")

            if isSingleWordSelection {
                Button {
                    Task { await quickExport() }
                } label: {
                    Label("Anki", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .help("Quick Export to Anki")
            } else {
                Button {
                    copyToClipboard(trimmedSelection, showFeedback: true)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .help("Copy Text")
            }

            Spacer(minLength: 0)

            overflowMenu
        }
        .controlSize(.small)
        .font(DS.Typography.caption.weight(.medium))
        .lineLimit(1)
        // Keeps ⌘E (export) and ⇧⌘X (stop) working while their menu is closed.
        .background(exportShortcutButton)
        .background(stopShortcutButton)
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

    // MARK: - Overflow Menu

    var overflowMenu: some View {
        Menu {
            if !isSingleWordSelection {
                Button(action: toggleSaveWord) {
                    Label(isCurrentlySaved ? "Remove from Saved" : "Save to Vocabulary",
                          systemImage: isCurrentlySaved ? "star.slash" : "star")
                }
                .disabled(!hasSelection)
            }

            Button {
                copyToClipboard(trimmedSelection, showFeedback: true)
            } label: {
                Label("Copy Text", systemImage: "doc.on.doc")
            }
            .disabled(!hasSelection)

            // Chosen from the selection now (one word: word, more: sentence);
            // still yours to override for this selection.
            Picker(selection: $explainMode) {
                ForEach(ExplainMode.allCases) { mode in
                    Text(mode.localizedTitle).tag(mode)
                }
            } label: {
                Label("Explain As", systemImage: "text.magnifyingglass")
            }

            Section("Anki") {
                Button {
                    Task { await quickExport() }
                } label: {
                    Label("Quick Export to Anki", systemImage: "square.and.arrow.up")
                }
                .disabled(!hasSelection)

                Button {
                    showAnkiExport = true
                } label: {
                    Label("Export Fields… (⌘E)", systemImage: "slider.horizontal.3")
                }
                .disabled(!hasSelection)
            }

            Divider()

            Button(role: .destructive) {
                viewModel.resetAll(); activeModule = nil
            } label: {
                Label("Clear Outputs", systemImage: "trash")
            }
            .disabled(isAnyLoading)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(DS.Typography.icon(13, weight: .medium))
                .foregroundStyle(DS.Color.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More actions")
    }

    /// Invisible button that keeps the ⌘E export shortcut active regardless of
    /// the overflow menu's open/closed state.
    private var exportShortcutButton: some View {
        Button { showAnkiExport = true } label: { Color.clear }
            .frame(width: 0, height: 0)
            .opacity(0)
            .keyboardShortcut("e", modifiers: [.command])
            .disabled(!hasSelection)
            .accessibilityHidden(true)
    }

    private var stopShortcutButton: some View {
        Button { speechManager.stop() } label: { Color.clear }
            .frame(width: 0, height: 0)
            .opacity(0)
            .keyboardShortcut("x", modifiers: [.command, .shift])
            .disabled(!speechManager.isSpeaking)
            .accessibilityHidden(true)
    }
}
