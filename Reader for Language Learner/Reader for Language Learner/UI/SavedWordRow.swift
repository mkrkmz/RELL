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

    @State private var isHovered = false

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            // Mastery dot — color reflects learning progress
            Circle()
                .fill(word.masteryLevel.color.opacity(0.7))
                .frame(width: 6, height: 6)
                .padding(.top, 5)
                .help(word.masteryLevel.label)

            VStack(alignment: .leading, spacing: DS.Spacing.xxs + 1) {
                // Term
                HStack(spacing: DS.Spacing.xs) {
                    Text(word.term)
                        .font(DS.Typography.callout.weight(.medium))
                        .foregroundStyle(DS.Color.textPrimary)
                        .lineLimit(1)
                    if isHovered {
                        SpeakButton(text: word.term, size: 11)
                            .transition(.opacity)
                    }
                }

                // Source + domain badge + date row
                HStack(spacing: DS.Spacing.xs) {
                    if let pdf = word.pdfFilename {
                        HStack(spacing: 3) {
                            Image(systemName: "doc.text")
                                .font(DS.Typography.icon(9))
                            Text(pdf)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .foregroundStyle(DS.Color.textTertiary)
                        if let p = word.pageNumber {
                            Text("p.\(p)")
                                .foregroundStyle(DS.Color.textTertiary)
                        }
                    }

                    // Domain badge (hidden for General to reduce noise)
                    let domain = DomainPreference(rawValue: word.domain) ?? .general
                    if domain != .general {
                        Text(domain.localizedTitle)
                            .font(DS.Typography.caption2.weight(.semibold))
                            .foregroundStyle(domain.badgeColor)
                            .padding(.horizontal, DS.Spacing.xs)
                            .padding(.vertical, 1)
                            .background(domain.badgeColor.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    if let cefr = word.cefrLevel.flatMap(CEFRLevel.init) {
                        HStack(spacing: 2) {
                            if word.cefrIsAuto {
                                Image(systemName: "sparkle")
                                    .font(DS.Typography.icon(7, weight: .semibold))
                            }
                            Text(cefr.rawValue)
                                .font(DS.Typography.caption2.weight(.semibold))
                        }
                        .foregroundStyle(cefr.badgeColor)
                        .padding(.horizontal, DS.Spacing.xs)
                        .padding(.vertical, 1)
                        .background(cefr.badgeColor.opacity(0.12))
                        .clipShape(Capsule())
                        .help(word.cefrIsAuto ? "AI-estimated level" : "CEFR level")
                    }

                    if let language = word.language.flatMap(Language.init) {
                        Text(language.flag)
                            .font(DS.Typography.caption2)
                            .help(language.nativeName)
                    }

                    Spacer()

                    // Mode indicator
                    let mode = ExplainMode(rawValue: word.mode) ?? .word
                    Image(systemName: mode == .word ? "character.cursor.ibeam" : "text.alignleft")
                        .foregroundStyle(DS.Color.textTertiary)

                    Text(Self.relativeFormatter.localizedString(for: word.savedAt, relativeTo: Date()))
                        .foregroundStyle(DS.Color.textTertiary)
                }
                .font(DS.Typography.caption2)

                HStack(spacing: DS.Spacing.xs) {
                    Label(word.reviewStatus.label, systemImage: word.reviewStatus.icon)
                        .font(DS.Typography.caption2.weight(.semibold))
                        .foregroundStyle(word.reviewStatus.color)

                    if let nextReviewAt = word.nextReviewAt, word.reviewStatus != .mastered {
                        Text("Next \(Self.relativeFormatter.localizedString(for: nextReviewAt, relativeTo: Date()))")
                            .font(DS.Typography.caption2)
                            .foregroundStyle(DS.Color.textTertiary)
                    }
                }

                // Tag chips
                if !word.tags.isEmpty {
                    FlowLayout(spacing: 3) {
                        ForEach(word.tags, id: \.self) { tag in
                            TagChip(tag: tag)
                        }
                    }
                    .padding(.top, 1)
                }

                // Notes snippet
                if !word.notes.isEmpty {
                    Text(word.notes)
                        .font(DS.Typography.caption2)
                        .foregroundStyle(DS.Color.textSecondary)
                        .lineLimit(1)
                        .italic()
                }

                // Module output dots — colored indicator per saved module
                let savedModules = ModuleType.allCases.filter {
                    !(word.llmOutputs[$0.rawValue] ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                if !savedModules.isEmpty {
                    HStack(spacing: DS.Spacing.xs) {
                        ForEach(savedModules) { module in
                            Circle()
                                .fill(module.accentColor.opacity(0.75))
                                .frame(width: 5, height: 5)
                        }
                    }
                    .padding(.top, 1)
                }

                // Definition snippet (from saved LLM output)
                if let defn = word.llmOutputs[ModuleType.definitionEN.rawValue]?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !defn.isEmpty {
                    Text(defn)
                        .font(DS.Typography.caption2)
                        .foregroundStyle(DS.Color.textTertiary)
                        .lineLimit(2)
                        .padding(.top, 1)
                }
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
}
