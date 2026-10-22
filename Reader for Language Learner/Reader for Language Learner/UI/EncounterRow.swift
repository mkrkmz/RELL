//
//  EncounterRow.swift
//  Reader for Language Learner
//
//  One sentence a saved word turned up in. Split out of
//  SavedWordDetailSheet.swift (v20 S0), unchanged.
//

import SwiftUI

/// One sentence the word turned up in, and where. Clicking opens the book
/// there; a document that's gone from disk shows the sentence but can't open.
struct EncounterRow: View {
    let encounter: WordEncounter
    let sentence: AttributedString
    let isAvailable: Bool
    let onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(sentence)
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Color.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                // The book's name is the heading above (v18 S5).
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: encounter.isEPUB ? "book" : "doc.text")
                        .font(DS.Typography.icon(10))
                    Text(WordPageModel.locationLabel(encounter))
                    Text("·")
                    Text(encounter.date, format: .relative(presentation: .named))
                    if encounter.occurrences > 1 {
                        Text("· ×\(encounter.occurrences)")
                    }
                    Spacer(minLength: 0)
                    if isAvailable && isHovered {
                        Image(systemName: "arrow.up.forward")
                            .font(DS.Typography.icon(10, weight: .semibold))
                    }
                }
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.textTertiary)
            }
            .padding(DS.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovered && isAvailable ? DS.Color.hoverOverlay : DS.Color.surfaceInset)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .onHover { isHovered = $0 }
        .help(isAvailable ? Text("Open at this page") : Text("This document is no longer on this Mac"))
    }
}
