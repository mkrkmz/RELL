//
//  InspectorView+Sentence.swift
//  Reader for Language Learner
//
//  A phrase or sentence in the inspector (v14 S2): the sentence and its
//  translation in a card with its actions. Since v18 S2 the passage tools —
//  Grammar, Simplify, Retell — are buttons on the card like the modules.
//

import SwiftUI

extension InspectorView {

    var sentenceCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                Text(trimmedSelection)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Color.textPrimary)
                    .lineLimit(4)
                    .truncationMode(.tail)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Selected text: \(trimmedSelection)")
                savedBadge
                recentTermsMenu
            }

            if let translation = cardTranslation {
                Text(translation)
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Color.textSecondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(.leading, DS.Spacing.sm)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(DS.Color.hairlineStrong).frame(width: 2)
                    }
            }

            // v18 S2: the actions, then the modules and passage tools on the card.
            cardActionsRow
                .padding(.top, DS.Spacing.xxs)
            cardModulesRow
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Gradient.accentWash)
        .dsCard(padding: nil)
        .animation(DS.Animation.standard, value: cardTranslation)
    }

    /// The translation strip's own result, read from the shared cache — the
    /// card never asks for a translation itself, so the two don't send the
    /// same request twice. Re-read whenever the cache gains an entry.
    private var cardTranslation: String? {
        _ = quickLookup.translationRevision
        return quickLookup.cachedTranslation(for: trimmedSelection)
    }
}
