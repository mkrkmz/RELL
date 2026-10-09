//
//  SavedWordRow.swift
//  Reader for Language Learner
//
//  One row of the saved-words list. Split out of `SavedWordsListView`
//  (v10 Sprint 4, T3).
//

import SwiftUI

struct SavedWordRow: View {
    let word: SavedWord
    /// The latest time this word turned up in your reading, if ever.
    var lastEncounter: WordEncounter? = nil

    @State private var isHovered = false

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    // v14 S3: three things per row — level and status, the meaning in one
    // line, and where you last met the word. Source page, domain, mode,
    // save date, tags, notes and the next review are on the word's page.
    // (Tags used a FlowLayout, which re-flows with the column's width — not
    // allowed in an AppKit-sized column since v14.)
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: DS.Spacing.xs) {
                Text(word.term)
                    .font(DS.Typography.callout.weight(.medium))
                    .foregroundStyle(DS.Color.textPrimary)
                    .lineLimit(1)
                if isHovered {
                    SpeakButton(text: word.term, size: 11)
                        .transition(.opacity)
                }

                Spacer(minLength: DS.Spacing.xs)

                if let language = word.language.flatMap(Language.init), language != Language.storedTarget {
                    Text(language.flag)
                        .font(DS.Typography.caption2)
                        .help(language.nativeName)
                }
                if word.hasTag(KindleVocabulary.deckName) {
                    Text("Kindle")
                        .font(DS.Typography.caption2.weight(.semibold))
                        .foregroundStyle(.purple)
                        .padding(.horizontal, DS.Spacing.xs)
                        .padding(.vertical, 1)
                        .background(Color.purple.opacity(0.12), in: Capsule())
                        .help("Imported from your Kindle")
                }
                if word.isStruggling {
                    Image(systemName: "exclamationmark.arrow.circlepath")
                        .font(DS.Typography.icon(10, weight: .semibold))
                        .foregroundStyle(DS.Color.danger)
                        .help("You keep forgetting this one")
                        .accessibilityLabel("You keep forgetting this one")
                }
                if let cefr = word.cefrLevel.flatMap(CEFRLevel.init) {
                    HStack(spacing: 2) {
                        if word.cefrIsAuto {
                            Image(systemName: "sparkle")
                                .font(DS.Typography.icon(7, weight: .semibold))
                        }
                        Text(cefr.rawValue)
                    }
                    .font(DS.Typography.caption2.weight(.semibold))
                    .foregroundStyle(cefr.badgeColor)
                    .padding(.horizontal, DS.Spacing.xs)
                    .padding(.vertical, 1)
                    .background(cefr.badgeColor.opacity(0.12), in: Capsule())
                    .help(word.cefrIsAuto ? "AI-estimated level" : "CEFR level")
                }
                Text(word.reviewStatus.label)
                    .font(DS.Typography.caption2.weight(.semibold))
                    .foregroundStyle(word.reviewStatus.color)
                    .padding(.horizontal, DS.Spacing.xs)
                    .padding(.vertical, 1)
                    .background(word.reviewStatus.color.opacity(0.12), in: Capsule())
                    .lineLimit(1)
            }

            if let meaning = Self.oneLineMeaning(of: word) {
                Text(AttributedResultView.markdown(meaning))
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textSecondary)
                    .lineLimit(1)
            } else {
                // v15 S1: say it's missing rather than leave a gap.
                Text("No meaning yet")
                    .font(DS.Typography.caption.italic())
                    .foregroundStyle(DS.Color.textTertiary)
                    .lineLimit(1)
            }

            if let lastMet = lastMetText {
                Text(lastMet)
                    .font(DS.Typography.caption2)
                    .foregroundStyle(DS.Color.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, DS.Spacing.xxs)
        .background(isHovered ? DS.Color.hoverOverlay : .clear)
        .onHover { isHovered = $0 }
        .animation(DS.Animation.fast, value: isHovered)
        .accessibilityElement(children: .combine)
        // `localizedTitle`, not `label`: VoiceOver should speak the mastery
        // level in the user's language like the rest of the row.
        .accessibilityLabel("\(word.term), \(word.masteryLevel.localizedTitle)")
        .accessibilityHint("Tap to view details")
        .accessibilityValue(word.pdfFilename.map { "from \($0)" } ?? "")
    }

    /// "Last met: <book> · <when>", or where it was saved when it hasn't
    /// turned up in your reading since.
    private var lastMetText: String? {
        if let lastEncounter {
            let when = Self.relativeFormatter.localizedString(for: lastEncounter.date, relativeTo: Date())
            return String(localized: "Last met: \(lastEncounter.documentTitle) · \(when)")
        }
        guard let source = word.pdfFilename else { return nil }
        let when = Self.relativeFormatter.localizedString(for: word.savedAt, relativeTo: Date())
        return String(localized: "Saved from \(source) · \(when)")
    }

    /// The meaning in your language if a module wrote one, else the
    /// definition — first line only.
    static func oneLineMeaning(of word: SavedWord) -> String? {
        for module in [ModuleType.meaningTR, .definitionEN] {
            let text = word.llmOutputs[module.rawValue] ?? ""
            if let line = text.split(whereSeparator: \.isNewline)
                .map({ $0.trimmingCharacters(in: .whitespaces) })
                .first(where: { !$0.isEmpty }) {
                return line
            }
        }
        return nil
    }
}
