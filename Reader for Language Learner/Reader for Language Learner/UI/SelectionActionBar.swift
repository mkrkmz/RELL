//
//  SelectionActionBar.swift
//  Reader for Language Learner
//
//  A compact floating action bar shown next to a live text selection so the
//  core reading-loop actions (save, analyze, highlight, speak, copy) are one
//  tap away, without a trip to the right-click menu or across to the inspector.
//  Shared by the PDF and EPUB readers; each host positions it and supplies the
//  action closures, which route into the reader's existing selection handlers.
//
//  It floats over the text, so it's an opaque, page-themed capsule rather
//  than glass (v14 S1 — see ReadingOverlay.swift).
//

import SwiftUI

struct SelectionActionBar: View {
    let onSave: () -> Void
    let onAnalyze: () -> Void
    let onHighlight: (HighlightColor) -> Void
    let onSpeak: () -> Void
    let onCopy: () -> Void
    /// Rewrite the selection at the reader's level (v13 S3).
    let onSimplify: () -> Void
    /// Retell the passage in your own words (v13 S4).
    let onRetell: () -> Void
    /// Simplify and Retell take a passage; for a word they show disabled,
    /// with the reason, rather than disappearing (v14 S1).
    var isPassage: Bool = false
    /// When the current selection is already in the vocabulary, the save button
    /// reads as "saved" rather than inviting a duplicate.
    var isSaved: Bool = false

    // v14 S1: the two actions used most are labelled; the rest are named in
    // a Tools menu, in the same order as the right-click menu
    // (`SelectionMenu`). Before, seven unlabelled icons.
    var body: some View {
        HStack(spacing: 2) {
            labelledButton(
                isSaved ? "Saved" : "Save",
                icon: isSaved ? "bookmark.fill" : "bookmark",
                prominent: !isSaved,
                help: isSaved ? "Saved" : "Save Word",
                action: onSave
            )
            labelledButton("Analyze", icon: "sparkles", prominent: false, help: "Analyze in the Inspector", action: onAnalyze)

            Divider()
                .frame(height: 16)
                .padding(.horizontal, 2)

            Button(action: onSpeak) {
                Image(systemName: "speaker.wave.2")
                    .font(DS.Typography.icon(13, weight: .medium))
                    .foregroundStyle(DS.Color.textPrimary)
                    .frame(width: 30, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Speak")
            .accessibilityLabel("Speak")

            toolsMenu
        }
        .padding(.horizontal, DS.Spacing.xxs)
        .padding(.vertical, DS.Spacing.xxs)
        .dsReadingOverlay(Capsule())
        .fixedSize()
    }

    private var toolsMenu: some View {
        Menu {
            Button(action: onSimplify) {
                Text("Simplify")
                if !isPassage { Text(SelectionMenu.passageOnlyReason) }
            }
            .disabled(!isPassage)
            Button(action: onRetell) {
                Text("Retell")
                if !isPassage { Text(SelectionMenu.passageOnlyReason) }
            }
            .disabled(!isPassage)

            Divider()

            Menu("Highlight") {
                ForEach(HighlightColor.allCases) { color in
                    Button {
                        onHighlight(color)
                    } label: {
                        Label {
                            Text(color.label)
                        } icon: {
                            Image(nsImage: SelectionMenu.swatchImage(for: color.nsColor))
                        }
                    }
                }
            }
            Button("Speak", action: onSpeak)
            Button("Copy", action: onCopy)
        } label: {
            Text("Tools")
                .font(DS.Typography.caption.weight(.medium))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .fixedSize()
        .padding(.horizontal, DS.Spacing.sm)
        .frame(height: 26)
        .help("Simplify, retell, highlight, speak, copy")
        .accessibilityLabel("Tools")
    }

    private func labelledButton(
        _ title: LocalizedStringKey,
        icon: String,
        prominent: Bool,
        help: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(DS.Typography.caption.weight(.semibold))
                .foregroundStyle(prominent ? SwiftUI.Color.white : DS.Color.accent)
                .padding(.horizontal, DS.Spacing.sm + 2)
                .frame(height: 26)
                .background(prominent ? DS.Color.accent : DS.Color.accentSubtle, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
