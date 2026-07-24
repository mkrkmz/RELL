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
//  Chrome, not content: a single neutral glass capsule with plain icon buttons
//  (per the "glass is chrome" rule and the calm single-accent design taste).
//

import SwiftUI

struct SelectionActionBar: View {
    let onSave: () -> Void
    let onAnalyze: () -> Void
    let onHighlight: () -> Void
    let onSpeak: () -> Void
    let onCopy: () -> Void
    /// When the current selection is already in the vocabulary, the save button
    /// reads as "saved" rather than inviting a duplicate.
    var isSaved: Bool = false

    var body: some View {
        HStack(spacing: 2) {
            barButton(
                icon: isSaved ? "bookmark.fill" : "bookmark",
                label: isSaved ? "Saved" : "Save Word",
                tint: isSaved ? DS.Color.accent : nil,
                action: onSave
            )
            barButton(icon: "sparkles", label: "Analyze", action: onAnalyze)
            barButton(icon: "highlighter", label: "Highlight", action: onHighlight)
            barButton(icon: "speaker.wave.2", label: "Speak", action: onSpeak)
            barButton(icon: "doc.on.doc", label: "Copy", action: onCopy)
        }
        .padding(.horizontal, DS.Spacing.xxs)
        .padding(.vertical, DS.Spacing.xxs)
        .dsGlassCapsule(fallback: AnyShapeStyle(.regularMaterial))
        .fixedSize()
    }

    private func barButton(
        icon: String,
        label: LocalizedStringKey,
        tint: SwiftUI.Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(DS.Typography.icon(14, weight: .medium))
                .foregroundStyle(tint ?? DS.Color.textPrimary)
                .frame(width: 30, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}
