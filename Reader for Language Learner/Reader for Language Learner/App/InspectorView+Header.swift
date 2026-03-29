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
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            // ── Word chip ─────────────────────────────────────────────────
            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                Text(trimmedSelection)
                    .font(DS.Typography.callout.weight(.medium))
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isCurrentlySaved {
                    Label("Saved", systemImage: "checkmark.seal.fill")
                        .font(DS.Typography.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, DS.Spacing.xxs + 1)
                        .background(DS.Color.success.opacity(0.85))
                        .clipShape(Capsule())
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .padding(DS.Spacing.md)
            .background(DS.Color.surfaceInset)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
            .animation(DS.Animation.springFast, value: isCurrentlySaved)

            // ── Action bar ────────────────────────────────────────────────
            actionBar
        }
        .padding(DS.Spacing.md)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        .dsShadow(DS.Shadow.subtle)
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
    }
}
