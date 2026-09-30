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

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                FlowLayout(spacing: DS.Spacing.xs) {
                    ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                        VStack(spacing: 1) {
                            Text(token.text)
                                .font(DS.Typography.callout)
                                .foregroundStyle(token.kind.color)
                            Text(token.kind.shortLabel)
                                .font(DS.Typography.micro(8, weight: .semibold))
                                .foregroundStyle(DS.Color.textTertiary)
                        }
                        .padding(.horizontal, 3)
                        .padding(.vertical, 2)
                        .background(token.kind.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                        .help(token.kind.localizedTitle)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(token.text), \(token.kind.localizedTitle)")
                    }
                }

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
            .padding(.top, DS.Spacing.xs)
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
                let raw = try await AppleOnDevice.chatWithFallback(
                    system: GrammarLens.systemPrompt(
                        target: language, native: Language.storedNative, level: CEFRLevel.storedLearnerLevel
                    ),
                    user: sentence,
                    temperature: 0.2,
                    maxTokens: GrammarLens.maxTokens
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
