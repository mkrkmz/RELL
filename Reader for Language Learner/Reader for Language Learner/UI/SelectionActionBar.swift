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
//  than glass (v14 S1 — see ReadingOverlay.swift). Its buttons are the quiet
//  ones (1.47.2, `DSButtonStyles` since v18 S1) — and it can be turned off in
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
            Button(action: onSave) {
                Label(isSaved ? "Saved" : "Save", systemImage: isSaved ? "bookmark.fill" : "bookmark")
            }
            .buttonStyle(.dsQuiet)
            .help(isSaved ? "Saved" : "Save Word")
            Button(action: onAnalyze) {
                Label("Analyze", systemImage: "sparkles")
            }
            .buttonStyle(.dsQuiet)
            .help("Analyze in the Inspector")

            Divider()
                .frame(height: 16)
                .padding(.horizontal, DS.Spacing.xxs)

            Button(action: onSpeak) {
                Label("Speak", systemImage: "speaker.wave.2")
            }
            .buttonStyle(.dsIcon)
            .help("Speak")

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

/// Where the selection bar goes (v18 S4, approved mockup): above the
/// selection, below it when there's no room above, and never on the
/// selected lines while either side has room. In a top-left coordinate
/// space (y grows down); the PDF reader, which isn't flipped, mirrors in.
nonisolated enum SelectionBarPlacement {
    static let gap: CGFloat = 8
    static let margin: CGFloat = 4

    /// The bar's top edge.
    static func originY(selectionTop: CGFloat, selectionBottom: CGFloat, barHeight: CGFloat,
                        visibleTop: CGFloat, visibleBottom: CGFloat) -> CGFloat {
        let above = selectionTop - gap - barHeight
        if above >= visibleTop + margin { return above }
        let below = selectionBottom + gap
        if below + barHeight <= visibleBottom - margin { return below }
        // A selection taller than the view: the top of what's visible.
        return visibleTop + margin
    }

    /// The bar's left edge: centred on the selection, kept inside the view.
    static func originX(selectionMidX: CGFloat, barWidth: CGFloat,
                        visibleLeft: CGFloat, visibleRight: CGFloat) -> CGFloat {
        let centred = selectionMidX - barWidth / 2
        return min(max(centred, visibleLeft + margin), max(visibleLeft + margin, visibleRight - barWidth - margin))
    }
}
