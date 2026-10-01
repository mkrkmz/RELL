//
//  InspectorView+Grammar.swift
//  Reader for Language Learner
//
//  The grammar lens (Roadmap v13 Sprint 5): for a phrase or sentence, each
//  word tagged with its part of speech — colour plus a label under it, so
//  it doesn't depend on telling colours apart — and, on request, a short
//  explanation of the structure.
//

import SwiftUI

extension InspectorView {

    @ViewBuilder
    var grammarLensSection: some View {
        if !isSingleWordSelection, GrammarLens.isEligible(trimmedSelection) {
            GrammarLensView(sentence: trimmedSelection, language: targetLanguage)
                .id(trimmedSelection)
        }
    }
}

struct GrammarLensView: View {
    let sentence: String
    let language: Language

    @AppStorage(StorageKey.grammarLensExpanded) private var expanded = false
    @State private var explanation: String?
    @State private var isExplaining = false
    @State private var failure: String?

    private var tokens: [GrammarLens.Token] { GrammarLens.tokens(in: sentence, language: language) }

    /// Each word in its part-of-speech colour with a small tag right after
    /// it — the tag carries the meaning for readers who can't tell the
    /// colours apart.
    private var taggedSentence: AttributedString {
        var result = AttributedString()
        for (index, token) in tokens.enumerated() {
            if index > 0 { result += AttributedString("  ") }
            var word = AttributedString(token.text)
            word.foregroundColor = token.kind.color
            word.font = DS.Typography.callout
            var tag = AttributedString("\u{2009}" + token.kind.shortLabel)
            tag.foregroundColor = DS.Color.textTertiary
            tag.font = DS.Typography.micro(8, weight: .semibold)
            result += word + tag
        }
        return result
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            // Scrolls inside a capped height. The inspector column doesn't
            // scroll as a whole — only the result panel flexes — so content
            // here that refused to shrink raised the column's minimum height
            // past the window's, and AppKit looped on the constraints until
            // it crashed (seen twice in v13 S5's live pass). A ScrollView's
            // minimum height is near zero; it can't do that.
            ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                Text(taggedSentence)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(tokens.map { "\($0.text), \($0.kind.localizedTitle)" }.joined(separator: "; "))

                if let explanation {
                    Text(explanation)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let failure {
                    Text(failure)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.danger)
                } else {
                    Button {
                        explain()
                    } label: {
                        HStack(spacing: DS.Spacing.xs) {
                            if isExplaining { ProgressView().controlSize(.mini) }
                            Text("Explain the Structure")
                        }
                    }
                    .buttonStyle(.link)
                    .font(DS.Typography.caption)
                    .disabled(isExplaining)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, DS.Spacing.xs)
            }
            .frame(maxHeight: 160)
        } label: {
            Label("Grammar", systemImage: "textformat.abc")
                .font(DS.Typography.caption.weight(.semibold))
                .foregroundStyle(DS.Color.textSecondary)
        }
        .padding(.horizontal, DS.Spacing.xs)
    }

    private func explain() {
        isExplaining = true
        failure = nil
        Task {
            do {
                // The configured provider, never Apple's on-device model: it
                // named simple-present sentences as past or continuous (see
                // `GrammarLens.systemPrompt`). No fallback to it either — a
                // wrong grammar explanation is worse than none.
                let raw = try await LLMConfiguration().makeProvider().chat(
                    system: GrammarLens.systemPrompt(
                        target: language, native: Language.storedNative, level: CEFRLevel.storedLearnerLevel
                    ),
                    user: GrammarLens.userPrompt(sentence: sentence, tokens: tokens),
                    temperature: 0,
                    maxTokens: GrammarLens.maxTokens,
                    topP: 0.9
                )
                explanation = ReadingRecap.clean(raw)
                if explanation == nil { failure = String(localized: "The AI returned nothing to show. Try again.") }
            } catch {
                failure = error.localizedDescription
            }
            isExplaining = false
        }
    }
}

extension GrammarLens.Kind {
    var color: Color {
        switch self {
        case .noun: return DS.Color.accent
        case .verb: return DS.Color.danger
        case .adjective: return DS.Color.success
        case .adverb: return DS.Color.warning
        case .pronoun: return .purple
        case .determiner, .particle, .other: return DS.Color.textSecondary
        case .preposition, .conjunction: return .teal
        case .number: return DS.Color.brown
        }
    }

    var localizedTitle: String {
        switch self {
        case .noun: return String(localized: "Noun")
        case .verb: return String(localized: "Verb")
        case .adjective: return String(localized: "Adjective")
        case .adverb: return String(localized: "Adverb")
        case .pronoun: return String(localized: "Pronoun")
        case .determiner: return String(localized: "Determiner")
        case .preposition: return String(localized: "Preposition")
        case .conjunction: return String(localized: "Conjunction")
        case .particle: return String(localized: "Particle")
        case .number: return String(localized: "Number")
        case .other: return String(localized: "Other")
        }
    }

    /// Two-to-four letter tag printed under the word.
    var shortLabel: String {
        switch self {
        case .noun: return String(localized: "N", comment: "grammar tag: noun")
        case .verb: return String(localized: "V", comment: "grammar tag: verb")
        case .adjective: return String(localized: "ADJ", comment: "grammar tag: adjective")
        case .adverb: return String(localized: "ADV", comment: "grammar tag: adverb")
        case .pronoun: return String(localized: "PRON", comment: "grammar tag: pronoun")
        case .determiner: return String(localized: "DET", comment: "grammar tag: determiner")
        case .preposition: return String(localized: "PREP", comment: "grammar tag: preposition")
        case .conjunction: return String(localized: "CONJ", comment: "grammar tag: conjunction")
        case .particle: return String(localized: "PART", comment: "grammar tag: particle")
        case .number: return String(localized: "NUM", comment: "grammar tag: number")
        case .other: return "·"
        }
    }
}
