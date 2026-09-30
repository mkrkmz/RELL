//
//  NextWordCard.swift
//  Reader for Language Learner
//
//  One due word in the menu bar window (Roadmap v13 Sprint 5): see it,
//  reveal the meaning, say whether you knew it. The answer goes to the
//  schedule like a flashcard's — it's recall.
//

import SwiftUI

struct NextWordCard: View {
    var store: SavedWordsStore

    @State private var revealed = false

    private var word: SavedWord? { store.dueWords().first }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack {
                Text("NEXT UP").dsOverlineLabel()
                Spacer()
                if store.pendingReviewCount > 1 {
                    Text("\(store.pendingReviewCount) due")
                        .font(DS.Typography.caption2)
                        .foregroundStyle(DS.Color.textTertiary)
                }
            }
            if let word {
                HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
                    Text(word.term)
                        .font(DS.Typography.wordDisplay)
                        .foregroundStyle(DS.Color.textPrimary)
                    SpeakButton(text: word.term, size: 12,
                                language: word.language.flatMap(Language.init(rawValue:)))
                    Spacer()
                }
                if revealed {
                    Text(InspectorView.firstLine(word.reviewDefinition))
                        .font(DS.Typography.callout)
                        .foregroundStyle(DS.Color.textSecondary)
                        .lineLimit(3)
                    HStack {
                        Button("Not Yet") { answer(.again, word) }
                        Spacer()
                        Button("I Knew It") { answer(.good, word) }
                            .buttonStyle(.borderedProminent)
                    }
                    .controlSize(.small)
                } else {
                    Button("Show Meaning") { revealed = true }
                        .controlSize(.small)
                }
            } else {
                Label("All caught up", systemImage: "checkmark.seal")
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Color.success)
            }
        }
        .padding(DS.Spacing.md)
        .animation(DS.Animation.standard, value: revealed)
        .animation(DS.Animation.standard, value: word?.id)
    }

    private func answer(_ rating: ReviewRating, _ word: SavedWord) {
        _ = store.applyReview(rating, to: word)
        revealed = false
    }
}
