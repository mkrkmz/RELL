//
//  InspectorView+Header.swift
//  Reader for Language Learner
//
//  Compact selection header + inline action bar + control strip.
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

    // MARK: - Compact Selection Header

    var selectionHeader: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                Text(trimmedSelection)
                    .font(DS.Typography.headline)
                    .foregroundStyle(DS.Color.textPrimary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Selected text: \(trimmedSelection)")

                if let savedWord = currentlySavedWord {
                    Label("Saved · \(savedWord.reviewStatus.label)", systemImage: savedWord.reviewStatus.icon)
                        .font(DS.Typography.caption2.weight(.semibold))
                        .foregroundStyle(savedWord.reviewStatus.color)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, 5)
                        .background(savedWord.reviewStatus.color.opacity(0.10))
                        .clipShape(Capsule())
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                        .accessibilityLabel("Word is saved to vocabulary. Review status: \(savedWord.reviewStatus.label)")
                }
            }
            .animation(DS.Animation.springFast, value: isCurrentlySaved)

            Divider()

            actionBar
        }
        .padding(.horizontal, DS.Spacing.xs)
        .padding(.top, DS.Spacing.xxs)
    }

    // MARK: - Control Strip (Mode + Detail + Recent Terms)

    var controlStrip: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            // Primary row: explain mode + detail level
            HStack(spacing: DS.Spacing.xs) {
                HStack(spacing: DS.Spacing.xxs) {
                    ForEach(ExplainMode.allCases) { mode in
                        Button { explainMode = mode } label: {
                            Text(mode.localizedTitle)
                                .font(DS.Typography.caption2.weight(explainMode == mode ? .bold : .regular))
                                .foregroundStyle(explainMode == mode ? DS.Color.accent : DS.Color.textTertiary)
                                .padding(.horizontal, DS.Spacing.sm)
                                .padding(.vertical, DS.Spacing.xxs + 1)
                                .background {
                                    if explainMode == mode {
                                        Capsule()
                                            .fill(DS.Color.accentSubtle)
                                            .matchedGeometryEffect(id: "modeBackground", in: moduleNamespace)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button {
                    explainDetail = explainDetail == .short ? .detailed : .short
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: explainDetail == .short ? "text.alignleft" : "text.alignjustify")
                            .font(DS.Typography.icon(10, weight: .medium))
                        Text(explainDetail == .short ? "Short" : "Detailed")
                            .font(DS.Typography.caption2)
                    }
                    .foregroundStyle(DS.Color.textTertiary)
                    .padding(.horizontal, DS.Spacing.sm)
                    .padding(.vertical, DS.Spacing.xxs + 1)
                    .background(DS.Color.cardSoft)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(DS.Color.hairline, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .help(explainDetail == .short ? "Switch to Detailed" : "Switch to Short")

                Spacer(minLength: 0)
            }

            // Secondary row: recent terms (de-emphasized subline)
            recentTermsRow
        }
        .padding(.horizontal, DS.Spacing.xs)
        .animation(DS.Animation.springFast, value: explainMode)
    }

    // MARK: - Recent Terms (secondary subline)

    @ViewBuilder
    private var recentTermsRow: some View {
        let recents = viewModel.recentTerms.filter {
            $0.lowercased() != trimmedSelection.lowercased()
        }.prefix(4)

        if !recents.isEmpty {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(DS.Typography.icon(9, weight: .medium))
                    .foregroundStyle(DS.Color.textTertiary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Spacing.xxs) {
                        ForEach(Array(recents), id: \.self) { term in
                            Button {
                                NotificationCenter.default.post(
                                    name: .inspectorRecentTermSelected,
                                    object: term
                                )
                            } label: {
                                Text(term)
                                    .font(DS.Typography.caption2)
                                    .foregroundStyle(DS.Color.textTertiary)
                                    .padding(.horizontal, DS.Spacing.xs)
                                    .padding(.vertical, DS.Spacing.xxs)
                                    .background(DS.Color.cardSoft)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Recent: \(term)")
                        }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Recent terms")
        }
    }

    // MARK: - Action Bar (compact inline)

    var actionBar: some View {
        // One glass container so the button chips sample a shared region
        // (glass cannot sample other glass). Spacing matches the layout.
        DSGlassGroup(spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.xs) {
                // Left cluster: playback
                actionGroup {
                    iconButton(
                        systemImage: speechManager.isSpeaking ? "speaker.wave.2.fill" : "play.fill",
                        help: speechManager.isSpeaking ? "Speaking selected text…" : "Speak selected text (⇧⌘S)",
                        action: speakSelection
                    )
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(!hasSelection)

                    iconButton(
                        systemImage: "stop.fill",
                        help: "Stop speaking (⇧⌘X)",
                        action: speechManager.stop
                    )
                    .keyboardShortcut("x", modifiers: [.command, .shift])
                    .disabled(!speechManager.isSpeaking)
                }

                Spacer(minLength: DS.Spacing.sm)

                // Right cluster: save + more
                actionGroup {
                    iconButton(
                        systemImage: isCurrentlySaved ? "star.fill" : "star",
                        help: isCurrentlySaved ? "Remove from saved vocabulary (⌘D)" : "Save to vocabulary (⌘D)",
                        action: toggleSaveWord
                    )
                    .keyboardShortcut("d", modifiers: [.command])
                    .foregroundStyle(isCurrentlySaved ? DS.Color.star : DS.Color.textPrimary)

                    overflowMenu
                }
            }
        }
        .controlSize(.mini)
        // Keeps ⌘E working even while the overflow menu is closed.
        .background(exportShortcutButton)
    }

    // MARK: - Overflow Menu

    private var overflowMenu: some View {
        Menu {
            Button {
                copyToClipboard(trimmedSelection, showFeedback: true)
            } label: {
                Label("Copy Text", systemImage: "doc.on.doc")
            }
            .disabled(!hasSelection)

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
                .font(DS.Typography.icon(12, weight: .medium))
                .frame(width: 28, height: 28)
                .dsGlassInteractive(cornerRadius: DS.Radius.sm)
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

    @ViewBuilder
    private func actionGroup<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: DS.Spacing.xxs) {
            content()
        }
    }
}
