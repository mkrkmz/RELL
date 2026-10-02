//
//  InspectorView+Sentence.swift
//  Reader for Language Learner
//
//  A phrase or sentence in the inspector (v14 S2): the sentence and its
//  translation in a card with its actions, then the tools that work on a
//  passage — the grammar lens, Simplify and Retell — in one place.
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

            quickActions
                .padding(.top, DS.Spacing.xxs)
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

    // MARK: - Tools

    /// Passage tools, offered for a phrase or sentence only.
    var sentenceTools: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            DSSectionHeader(String(localized: "Tools"))
                .padding(.horizontal, DS.Spacing.xxs)

            grammarLensSection

            let isPassage = GradedRewrite.isEligible(trimmedSelection)
            HStack(spacing: DS.Spacing.xs) {
                Button {
                    NotificationCenter.default.post(name: .simplifySelectionCommand, object: trimmedSelection)
                } label: {
                    Label("Simplify", systemImage: "text.badge.checkmark")
                }
                Button {
                    NotificationCenter.default.post(name: .retellSelectionCommand, object: trimmedSelection)
                } label: {
                    Label("Retell", systemImage: "square.and.pencil")
                }
                Spacer(minLength: 0)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!isPassage)
            .help(isPassage ? Text("Simplify to your level, or retell it in your own words") : Text(SelectionMenu.passageOnlyReason))
        }
    }
}
