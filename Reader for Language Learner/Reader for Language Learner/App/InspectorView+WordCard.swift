//
//  InspectorView+WordCard.swift
//  Reader for Language Learner
//
//  The word card at the top of the inspector (Roadmap v13 Sprint 3): for a
//  single word, the word itself large, its sound, and a one-line meaning
//  from the hover dictionary's cache — often enough without running a
//  module. Saved words also show their level and how often they've come up.
//

import SwiftUI

extension InspectorView {

    /// A single word rather than a phrase or sentence — the card is for words.
    var isSingleWordSelection: Bool {
        explainMode == .word
            && !trimmedSelection.isEmpty
            && trimmedSelection.count <= 40
            && !trimmedSelection.contains(where: \.isWhitespace)
    }

    var wordCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
                Text(trimmedSelection)
                    .font(DS.Typography.wordDisplay)
                    .foregroundStyle(DS.Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .textSelection(.enabled)
                    .accessibilityLabel("Selected word: \(trimmedSelection)")
                SpeakButton(text: trimmedSelection, size: 13, language: targetLanguage)
                Spacer(minLength: 0)
                if let savedWord = currentlySavedWord {
                    if let cefr = savedWord.cefrLevel, let level = CEFRLevel(rawValue: cefr) {
                        Text(level.rawValue)
                            .font(DS.Typography.caption2.weight(.bold))
                            .foregroundStyle(level.badgeColor)
                            .padding(.horizontal, DS.Spacing.xs)
                            .padding(.vertical, 2)
                            .background(level.badgeColor.opacity(0.12), in: Capsule())
                    }
                    Label(savedWord.reviewStatus.label, systemImage: savedWord.reviewStatus.icon)
                        .labelStyle(.iconOnly)
                        .foregroundStyle(savedWord.reviewStatus.color)
                        .help(Text("Saved · \(savedWord.reviewStatus.label)"))
                }
            }

            Group {
                if let quickMeaning = inspectorQuickMeaning {
                    Text(quickMeaning)
                        .foregroundStyle(DS.Color.textSecondary)
                } else {
                    Text("Looking up…")
                        .foregroundStyle(DS.Color.textTertiary)
                }
            }
            .font(DS.Typography.callout)
            .lineLimit(2)
            .textSelection(.enabled)

            if let savedWord = currentlySavedWord,
               let summary = WordPageModel.encounterSummary(encounterStore?.encounters(for: savedWord.id) ?? []) {
                Label(summary, systemImage: "book.pages")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
            }
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Gradient.accentWash)
        .dsCard(padding: nil)
        .task(id: trimmedSelection) { await loadQuickMeaning(for: trimmedSelection) }
    }

    /// The hover dictionary's answer, cached or fetched once. It honours the
    /// "answer in" setting the same way the popover does; a failure leaves the
    /// line empty rather than showing an error above the modules.
    func loadQuickMeaning(for term: String) async {
        inspectorQuickMeaning = nil
        guard isSingleWordSelection else { return }
        if let cached = quickLookup.cachedHoverDefinition(for: term, savedWordsStore: savedWordsStore) {
            inspectorQuickMeaning = Self.firstLine(cached)
            return
        }
        guard let fetched = try? await quickLookup.hoverDefinition(for: term),
              !Task.isCancelled, term == trimmedSelection
        else { return }
        inspectorQuickMeaning = Self.firstLine(fetched)
    }

    /// First sentence of a definition, sanitised — the card is a glance.
    static func firstLine(_ text: String) -> String {
        let clean = MarkdownUtils.sanitizeLLMOutput(text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines).first ?? ""
        if let end = clean.firstIndex(where: { ".!?".contains($0) }),
           clean.distance(from: clean.startIndex, to: end) > 12 {
            return String(clean[...end])
        }
        return clean
    }
}
