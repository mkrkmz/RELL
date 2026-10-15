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
//  than glass (v14 S1 — see ReadingOverlay.swift). Since 1.47.2 its buttons
//  have no fill: labels in the page's text colour, colour only in the icons,
//  a faint highlight under the pointer — and it can be turned off in
//  Settings ▸ Reading (the right-click menu and the Inspector do the same).
//

import SwiftUI

struct SelectionActionBar: View {
    /// Settings ▸ Reading ▸ Selection Bar (1.47.2); on by default.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: StorageKey.selectionBarEnabled) as? Bool ?? true
    }

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
            BarButton(title: isSaved ? "Saved" : "Save",
                      icon: isSaved ? "bookmark.fill" : "bookmark",
                      help: isSaved ? "Saved" : "Save Word",
                      action: onSave)
            BarButton(title: "Analyze", icon: "sparkles", help: "Analyze in the Inspector", action: onAnalyze)

            Divider()
                .frame(height: 16)
                .padding(.horizontal, DS.Spacing.xxs)

            BarButton(title: nil, icon: "speaker.wave.2", help: "Speak", action: onSpeak)

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
                .foregroundStyle(DS.Color.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .fixedSize()
        .padding(.horizontal, DS.Spacing.sm)
        .frame(height: 26)
        .help("Simplify, retell, highlight, speak, copy")
        .accessibilityLabel("Tools")
    }
}

/// A bar button without a fill (1.47.2): the icon in the accent colour, the
/// label in the page's text colour, a faint highlight under the pointer.
private struct BarButton: View {
    let title: LocalizedStringKey?
    let icon: String
    let help: LocalizedStringKey
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: icon)
                    .font(DS.Typography.icon(12, weight: .semibold))
                    .foregroundStyle(DS.Color.accent)
                if let title {
                    Text(title)
                        .font(DS.Typography.caption.weight(.semibold))
                        .foregroundStyle(DS.Color.textPrimary)
                }
            }
            .padding(.horizontal, title == nil ? DS.Spacing.sm : DS.Spacing.sm + 2)
            .frame(height: 26)
            .background(hovering ? DS.Color.hoverOverlay : .clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(title ?? help)
    }
}
