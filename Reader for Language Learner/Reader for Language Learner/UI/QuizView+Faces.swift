//
//  QuizView+Faces.swift
//  Reader for Language Learner
//
//  The card faces. Split out of QuizView.swift (v19 S0), unchanged.
//

import SwiftUI

extension QuizView {

    // MARK: - Card Faces

    func cardFace(content: some View, isFront: Bool) -> some View {
        VStack(spacing: 0) {
            // v18 S5: in the room, a coloured band says what this card is.
            if style == .room, !quizMode.isRoundBased, let word = session.currentWord {
                roomBand(for: word)
            }
            content
                .padding(style == .room ? DS.Spacing.xl : DS.Spacing.lg)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, minHeight: style == .room ? 300 : DS.Layout.cardFrontMinHeight, alignment: .top)
        .dsCard(padding: nil, radius: DS.Radius.lg, stroke: .hairlineStrong)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
        .dsShadow(DS.Shadow.card)
        .padding(.horizontal, DS.Spacing.md)
    }

    @ViewBuilder
    func frontContent(for word: SavedWord) -> some View {
        if style == .room {
            roomFront(for: word)
        } else {
            sidebarFront(for: word)
        }
    }

    func sidebarFront(for word: SavedWord) -> some View {
        VStack(spacing: DS.Spacing.sm) {
            Text("TERM")
                .font(DS.Typography.caption2.weight(.bold))
                .foregroundStyle(DS.Color.textTertiary)
            HStack(spacing: DS.Spacing.sm) {
                Text(word.term)
                    .font(DS.Typography.wordDisplayLarge)
                    .foregroundStyle(DS.Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.72)
                SpeakButton(text: word.term, size: 15)
            }
            masteryBadge(word.masteryLevel)
            sourceBadge(for: word)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Review card front: \(word.term), mastery level \(word.masteryLevel.label), status \(word.reviewStatus.label)")
        .accessibilityHint("Tap to flip and see the definition")
    }

    /// Flashcard back: every saved module, summary-first with "Show more".
    @ViewBuilder
    func backContent(for word: SavedWord) -> some View {
        if style == .room {
            roomBack(for: word)
        } else {
            backSections(for: word, maxHeight: DS.Layout.cardBackHeightExpanded)
        }
    }

    /// Reveal card for choice/typed modes — the question hid the term, so the
    /// reveal leads with it before the saved content.
    func revealContent(for word: SavedWord) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                Text(word.term)
                    .font(DS.Typography.wordDisplay)
                    .foregroundStyle(DS.Color.textPrimary)
                    .minimumScaleFactor(0.72)
                SpeakButton(text: word.term, size: 13)
                Spacer(minLength: 0)
                masteryBadge(word.masteryLevel)
            }
            Divider()
            backSections(for: word, maxHeight: DS.Layout.cardBackHeightCompact)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Scrollable, labeled sections for all saved module outputs.
    /// Definition + native meaning show by default; the rest expand on demand.
    func backSections(for word: SavedWord, maxHeight: CGFloat) -> some View {
        let saved = savedModules(for: word)
        let summary = saved.filter { Self.summaryModules.contains($0) }
        // If neither summary module was saved, promote the first output so the
        // back is never just a "Show more" button.
        let visible = summary.isEmpty ? Array(saved.prefix(1)) : summary
        let hidden = saved.filter { !visible.contains($0) }
        // v15 S1: no meaning or definition saved — show the dictionary's,
        // read live; "Add to Card" keeps it.
        let preview = summary.isEmpty ? enricher?.dictionaryPreview(for: word) : nil

        return cardScroll(maxHeight: maxHeight) {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                if let preview {
                    dictionaryPreviewSection(preview, word: word)
                }
                if saved.isEmpty {
                    // No LLM outputs at all — fall back to sentence/placeholder.
                    if preview == nil || !word.sentence.isEmpty {
                        Text(word.reviewDefinition)
                            .font(DS.Typography.body)
                            .foregroundStyle(DS.Color.textPrimary)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    ForEach(visible) { module in
                        moduleSection(module, word: word)
                    }

                    if !hidden.isEmpty {
                        if session.showAllBackSections {
                            ForEach(hidden) { module in
                                moduleSection(module, word: word)
                            }
                        } else {
                            Button {
                                withAnimation(DS.Animation.standard) { session.showAllBackSections = true }
                            } label: {
                                Label("Show more (\(hidden.count))", systemImage: "chevron.down")
                                    .font(DS.Typography.caption2.weight(.semibold))
                                    .foregroundStyle(DS.Color.accent)
                            }
                            .buttonStyle(.plain)
                            .help("Show the other saved modules for this word")
                        }
                    }
                }

                sourceBadge(for: word)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The dictionary's answer on a card back that had nothing to show.
    func dictionaryPreviewSection(_ preview: FillResult, word: SavedWord) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            HStack(spacing: DS.Spacing.xs) {
                Text(String(localized: "FROM THE DICTIONARY"))
                    .font(DS.Typography.caption2.weight(.bold))
                    .foregroundStyle(DS.Color.textTertiary)
                Spacer(minLength: 0)
                Button("Add to Card") { enricher?.addDictionaryAnswer(to: word.id) }
                    .controlSize(.small)
                    .help("Keep this on the card")
            }
            Text(preview.value)
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Color.textPrimary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One labeled section on the card back (module dot + title + output).
    func moduleSection(_ module: ModuleType, word: SavedWord) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            HStack(spacing: DS.Spacing.xs) {
                Circle()
                    .fill(module.accentColor)
                    .frame(width: 5, height: 5)
                Text(module.title.uppercased())
                    .font(DS.Typography.caption2.weight(.bold))
                    .foregroundStyle(DS.Color.textTertiary)
            }
            Text(MarkdownUtils.sanitizeLLMOutput(word.llmOutputs[module.rawValue] ?? ""))
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Color.textPrimary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Modules with a non-empty saved output, in canonical module order.
    func savedModules(for word: SavedWord) -> [ModuleType] {
        ModuleType.allCases.filter {
            !(word.llmOutputs[$0.rawValue] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Bounded scroll container used by card bodies so long content scrolls
    /// inside the card instead of overflowing the sidebar.
    func cardScroll<Content: View>(
        maxHeight: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: maxHeight)
    }
}
