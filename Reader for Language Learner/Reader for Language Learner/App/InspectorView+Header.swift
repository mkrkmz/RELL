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
        savedWordsStore.isSaved(
            term: trimmedSelection,
            pdfFilename: pdfFilename,
            pageNumber: pageNumber
        )
    }

    // MARK: - Compact Selection Header

    var selectionHeader: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            // Row 1: Selected text + saved icon
            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                Text(trimmedSelection)
                    .font(DS.Typography.headline)
                    .foregroundStyle(DS.Color.textPrimary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Selected text: \(trimmedSelection)")

                if isCurrentlySaved {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.Color.success)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                        .accessibilityLabel("Word is saved to vocabulary")
                }
            }
            .animation(DS.Animation.springFast, value: isCurrentlySaved)

            // Row 2: Inline action icons
            actionBar
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xs)
    }

    // MARK: - Control Strip (Mode + Detail + Recent Terms)

    var controlStrip: some View {
        HStack(spacing: DS.Spacing.xs) {
            // Mode toggle: Word / Sentence
            ForEach(ExplainMode.allCases) { mode in
                Button { explainMode = mode } label: {
                    Text(mode.rawValue)
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

            // Detail toggle
            Button {
                explainDetail = explainDetail == .short ? .detailed : .short
            } label: {
                Image(systemName: explainDetail == .short ? "text.alignleft" : "text.alignjustify")
                    .font(.system(size: 10))
                    .foregroundStyle(DS.Color.textTertiary)
                    .padding(.horizontal, DS.Spacing.xs)
                    .padding(.vertical, DS.Spacing.xxs + 1)
                    .background(DS.Color.surfaceElevated)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(explainDetail == .short ? "Switch to Detailed" : "Switch to Short")

            // Recent terms (inline, trailing)
            recentTermsInline

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xxs)
        .animation(DS.Animation.springFast, value: explainMode)
    }

    // MARK: - Recent Terms (inline)

    @ViewBuilder
    private var recentTermsInline: some View {
        let recents = viewModel.recentTerms.filter {
            $0.lowercased() != trimmedSelection.lowercased()
        }.prefix(4)

        if !recents.isEmpty {
            Divider()
                .frame(height: 12)
                .padding(.horizontal, DS.Spacing.xxs)

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
                                .foregroundStyle(DS.Color.accent)
                                .padding(.horizontal, DS.Spacing.xs)
                                .padding(.vertical, DS.Spacing.xxs)
                                .background(DS.Color.accentSubtle)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Recent: \(term)")
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Recent terms")
        }
    }

    // MARK: - Action Bar (compact inline)

    var actionBar: some View {
        HStack(spacing: DS.Spacing.xxs) {
            // Playback
            iconButton(
                systemImage: speechManager.isSpeaking ? "speaker.wave.2.fill" : "play.fill",
                help: speechManager.isSpeaking ? "Speaking…" : "Speak (⇧⌘S)",
                action: speakSelection
            )
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(!hasSelection)

            iconButton(
                systemImage: "stop.fill",
                help: "Stop (⇧⌘X)",
                action: speechManager.stop
            )
            .keyboardShortcut("x", modifiers: [.command, .shift])
            .disabled(!speechManager.isSpeaking)

            actionSpacer()

            // Edit
            iconButton(systemImage: "doc.on.doc", help: "Copy") {
                copyToClipboard(trimmedSelection, showFeedback: true)
            }

            iconButton(
                systemImage: isCurrentlySaved ? "star.fill" : "star",
                help: isCurrentlySaved ? "Unsave (⌘D)" : "Save (⌘D)",
                action: toggleSaveWord
            )
            .keyboardShortcut("d", modifiers: [.command])
            .foregroundStyle(isCurrentlySaved ? .yellow : .primary)

            iconButton(systemImage: "square.and.arrow.up", help: "Quick Export") {
                Task { await quickExport() }
            }

            iconButton(systemImage: "ellipsis.circle", help: "Full Export… (⌘E)") {
                showAnkiExport = true
            }
            .keyboardShortcut("e", modifiers: [.command])

            actionSpacer()

            // Utility
            iconButton(systemImage: "trash", help: "Clear outputs", role: .destructive) {
                viewModel.resetAll(); activeModule = nil
            }
            .disabled(isAnyLoading)

            iconButton(systemImage: "gearshape", help: "Settings (⌘,)") {
                openSettings()
            }
            .keyboardShortcut(",", modifiers: [.command])
        }
        .controlSize(.mini)
    }
}
