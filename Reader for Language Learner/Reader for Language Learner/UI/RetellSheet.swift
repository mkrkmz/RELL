//
//  RetellSheet.swift
//  Reader for Language Learner
//
//  "Retell in your own words" (Roadmap v13 Sprint 4): the reader rewrites a
//  passage from memory, the AI corrects it, and every change is shown word
//  by word — removed struck through, added in bold, not colour alone.
//  Words the correction brought in can be saved with one click. Practice
//  only: nothing reaches the review schedule.
//

import SwiftUI

struct RetellSheet: View {
    let source: String

    @Environment(\.dismiss) private var dismiss
    @Environment(SavedWordsStore.self) private var savedWordsStore

    @State private var retelling = ""
    @State private var showPassage = true
    @State private var feedback: Retell.Feedback?
    @State private var failure: String?
    @State private var isChecking = false

    private var segments: [WordDiff.Segment] {
        feedback.map { WordDiff.diff(retelling, $0.corrected) } ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack {
                Text("Retell in Your Own Words")
                    .font(DS.Typography.headline)
                Spacer()
                Toggle("Show Passage", isOn: $showPassage)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help(Text("Hide it to retell from memory"))
            }

            if showPassage {
                ScrollView {
                    Text(source)
                        .font(DS.Typography.callout)
                        .foregroundStyle(DS.Color.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(DS.Spacing.sm)
                }
                .frame(maxHeight: 110)
                .background(DS.Color.surfaceInset)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
            }

            if let feedback {
                result(feedback)
            } else {
                TextEditor(text: $retelling)
                    .font(DS.Typography.body)
                    .scrollContentBackground(.hidden)
                    .padding(DS.Spacing.sm)
                    .background(DS.Color.surfaceInset)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
                    .frame(minHeight: 140)
                    .disabled(isChecking)
            }

            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.danger)
            }

            HStack {
                if isChecking {
                    ProgressView().controlSize(.small)
                    Text("Checking…")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                }
                Spacer()
                if feedback != nil {
                    Button("Try Again") { feedback = nil }
                }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if feedback == nil {
                    Button("Check") { check() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(retelling.split(whereSeparator: \.isWhitespace).count < 3 || isChecking)
                }
            }
        }
        .padding(DS.Spacing.lg)
        .frame(width: 620, height: 560)
    }

    private func result(_ feedback: Retell.Feedback) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("YOUR TEXT, CORRECTED").dsOverlineLabel()
                    Text(diffText)
                        .font(DS.Typography.body)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                }
                if !feedback.note.isEmpty {
                    Label(feedback.note, systemImage: "lightbulb")
                        .font(DS.Typography.callout)
                        .foregroundStyle(DS.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                let added = WordDiff.addedWords(segments)
                if !added.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text("WORDS FROM THE CORRECTION").dsOverlineLabel()
                        FlowChips(words: added, isSaved: isSaved, onSave: save)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Spacing.sm)
        }
        .background(DS.Color.surfaceInset)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
    }

    /// Removed: struck through and red. Added: bold and green. The strike
    /// and the weight carry the meaning for readers who can't tell the colours.
    private var diffText: AttributedString {
        var result = AttributedString()
        for (index, segment) in segments.enumerated() {
            var part = AttributedString((index == 0 ? "" : " ") + segment.text)
            switch segment.kind {
            case .same:
                part.foregroundColor = DS.Color.textPrimary
            case .removed:
                part.foregroundColor = DS.Color.danger
                part.strikethroughStyle = .single
            case .added:
                part.foregroundColor = DS.Color.success
                part.inlinePresentationIntent = .stronglyEmphasized
            }
            result += part
        }
        return result
    }

    private func isSaved(_ word: String) -> Bool {
        savedWordsStore.lemmaMatchedWord(for: word) != nil
    }

    private func save(_ word: String) {
        guard !isSaved(word), let corrected = feedback?.corrected else { return }
        let entry = EncounterScanner.Entry(id: UUID(), term: word)
        let sentence = EncounterScanner.scan(text: corrected, vocabulary: [entry], language: Language.storedTarget)
            .first?.sentence ?? ""
        savedWordsStore.add(SavedWord(term: word, sentence: sentence, language: Language.storedTarget.rawValue))
    }

    private func check() {
        isChecking = true
        failure = nil
        let original = GradedRewrite.input(source)
        let text = retelling
        Task {
            do {
                let raw = try await AppleOnDevice.chatWithFallback(
                    system: Retell.systemPrompt(
                        target: Language.storedTarget,
                        native: Language.storedNative,
                        level: CEFRLevel.storedLearnerLevel
                    ),
                    user: Retell.userPrompt(original: original, retelling: text),
                    temperature: 0.2,
                    maxTokens: Retell.maxTokens
                )
                if let parsed = Retell.parse(raw) {
                    feedback = parsed
                } else {
                    failure = String(localized: "The AI's answer couldn't be read. Try again.")
                }
            } catch {
                failure = error.localizedDescription
            }
            isChecking = false
        }
    }
}

/// Word chips that wrap onto new lines.
private struct FlowChips: View {
    let words: [String]
    let isSaved: (String) -> Bool
    let onSave: (String) -> Void

    var body: some View {
        FlowLayout(spacing: DS.Spacing.xs) {
            ForEach(words, id: \.self) { word in
                let saved = isSaved(word)
                Button { onSave(word) } label: {
                    Label(word, systemImage: saved ? "star.fill" : "star")
                        .font(DS.Typography.caption)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, DS.Spacing.xxs)
                        .background(DS.Color.accent.opacity(saved ? 0.18 : 0.08), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(saved ? DS.Color.star : DS.Color.accent)
                .disabled(saved)
                .help(saved ? Text("Saved") : Text("Save word"))
            }
        }
    }
}
