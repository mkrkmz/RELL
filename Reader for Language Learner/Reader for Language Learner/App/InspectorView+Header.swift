//
//  InspectorView+Header.swift
//  Reader for Language Learner
//
//  Selection header card (word chip + saved badge) and action bar.
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

    // MARK: - Selection Header

    var selectionHeader: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack(alignment: .top, spacing: DS.Spacing.md) {
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text(explainMode == .word ? "Selected Expression" : "Selected Sentence")
                            .dsOverlineLabel()

                        Text(trimmedSelection)
                            .font(DS.Typography.title)
                            .lineLimit(4)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel("Selected text: \(trimmedSelection)")
                    }

                    if isCurrentlySaved {
                        Label("Saved", systemImage: "checkmark.seal.fill")
                            .font(DS.Typography.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, DS.Spacing.sm)
                            .padding(.vertical, DS.Spacing.xxs + 1)
                            .background(DS.Color.success.opacity(0.9))
                            .clipShape(Capsule())
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                            .accessibilityLabel("Word is saved to vocabulary")
                    }
                }

                selectionMetaRow
            }
            .padding(DS.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .fill(
                        LinearGradient(
                            colors: [
                                DS.Color.accentSubtle,
                                DS.Color.surfaceElevated
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .strokeBorder(DS.Color.separator.opacity(0.45), lineWidth: 0.8)
            )
            .animation(DS.Animation.springFast, value: isCurrentlySaved)

            actionBar
        }
        .padding(DS.Spacing.md)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        .dsShadow(DS.Shadow.subtle)
    }

    var selectionMetaRow: some View {
        HStack(spacing: DS.Spacing.xs) {
            selectionMetaPill(
                title: explainMode.rawValue,
                value: explainDetail.rawValue,
                icon: explainMode == .word ? "character.cursor.ibeam" : "text.alignleft"
            )

            selectionMetaPill(
                title: "Length",
                value: "\(trimmedSelection.split(separator: " ").count) words",
                icon: "textformat.abc"
            )

            if let pageNumber {
                selectionMetaPill(
                    title: "Page",
                    value: "\(pageNumber)",
                    icon: "doc.text"
                )
            }

            Spacer(minLength: 0)
        }
    }

    func selectionMetaPill(title: String, value: String, icon: String) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            VStack(alignment: .leading, spacing: 1) {
                Text(title.uppercased())
                    .font(DS.Typography.caption2.weight(.bold))
                Text(value)
                    .font(DS.Typography.caption)
            }
        }
        .foregroundStyle(DS.Color.textSecondary)
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xs)
        .background(DS.Color.surface.opacity(0.75))
        .clipShape(Capsule())
    }

    // MARK: - Recent Terms

    /// Session-scoped history strip shown below the selection header.
    @ViewBuilder
    var recentTermsStrip: some View {
        let recents = viewModel.recentTerms.filter {
            $0.lowercased() != trimmedSelection.lowercased()
        }.prefix(6)

        if !recents.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.xs) {
                    Text("Recent:")
                        .font(DS.Typography.caption2.weight(.semibold))
                        .foregroundStyle(DS.Color.textTertiary)

                    ForEach(Array(recents), id: \.self) { term in
                        Button {
                            // Re-select this term by posting a synthetic selection change
                            NotificationCenter.default.post(
                                name: .inspectorRecentTermSelected,
                                object: term
                            )
                        } label: {
                            Text(term)
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Color.accent)
                                .padding(.horizontal, DS.Spacing.sm)
                                .padding(.vertical, DS.Spacing.xxs + 1)
                                .background(DS.Color.accentSubtle)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Recent term: \(term)")
                        .accessibilityHint("Tap to analyze this term")
                    }
                }
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.xs)
            }
            .background(DS.Color.surfaceElevated.opacity(0.6))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Recent terms")
        }
    }

    // MARK: - Action Bar

    var actionBar: some View {
        HStack(spacing: 0) {
            // Playback group
            Group {
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
            }

            actionSpacer()

            // Edit group
            Group {
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

                iconButton(systemImage: "square.and.arrow.up", help: "Quick Export to Anki") {
                    Task { await quickExport() }
                }

                iconButton(systemImage: "ellipsis.circle", help: "Full Export… (⌘E)") {
                    showAnkiExport = true
                }
                .keyboardShortcut("e", modifiers: [.command])
            }

            actionSpacer()

            // Utility group
            Group {
                iconButton(systemImage: "trash", help: "Clear outputs", role: .destructive) {
                    viewModel.resetAll(); activeModule = nil
                }
                .disabled(isAnyLoading)

                iconButton(systemImage: "gearshape", help: "Settings (⌘,)") {
                    openSettings()
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }
        .controlSize(.small)
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xs)
        .background(DS.Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .strokeBorder(DS.Color.separator.opacity(0.35), lineWidth: 0.8)
        )
    }
}
