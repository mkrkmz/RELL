//
//  SentenceWritingCard.swift
//  Reader for Language Learner
//
//  "Write a Sentence" (Roadmap v19 Sprint 3, approved mockup): the word,
//  its meaning and the sentence you met it in; you write one of your own;
//  the AI corrects it word by word, says why and gives a natural example.
//  The corrected sentence can be kept as a sentence card. The study room
//  runs it word after word; a word's page opens it for that word alone.
//  Practice: nothing reaches the review schedule.
//

import SwiftUI

struct SentenceWritingCard: View {
    let word: SavedWord
    /// Each checked sentence, for the session's summary.
    var onChecked: (SentenceWriting.Feedback) -> Void = { _ in }
    var onSaved: () -> Void = {}
    /// The next word; nil on a word's page, where the button closes instead.
    var onNext: (() -> Void)?
    var onDone: (() -> Void)?

    @Environment(SavedWordsStore.self) private var store
    @Environment(QuickLookupService.self) private var quickLookup: QuickLookupService?

    @State private var text = ""
    @State private var feedback: SentenceWriting.Feedback?
    @State private var written = ""
    @State private var failure: String?
    @State private var isChecking = false
    @State private var saved = false
    @State private var task: Task<Void, Never>?
    @AppStorage(StorageKey.sentenceWritingShowsBookSentence) private var showsBookSentence = true
    @FocusState private var fieldFocused: Bool

    private var language: Language { word.language.flatMap(Language.init(rawValue:)) ?? Language.storedTarget }
    private var sense: String? { FillField.meaning.value(in: word) ?? FillField.definition.value(in: word) }

    var body: some View {
        VStack(spacing: DS.Spacing.md) {
            header
            if let feedback {
                result(feedback)
            } else {
                editor
            }
            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            buttons
        }
        .frame(maxWidth: .infinity)
        // After the room takes focus for its keys, so the field gets it.
        .onAppear { DispatchQueue.main.async { fieldFocused = true } }
        .onChange(of: word.id) { _, _ in reset() }
        .onDisappear { task?.cancel() }
    }

    // MARK: Parts

    private var header: some View {
        VStack(spacing: DS.Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
                Text(word.term)
                    .font(DS.Typography.studyWord)
                    .foregroundStyle(DS.Color.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                SpeakButton(text: word.term, size: 16, language: language)
            }
            if let sense {
                Text(sense)
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            if !word.sentence.isEmpty {
                if showsBookSentence {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
                        Text(WordPageModel.emphasized(word.sentence, term: word.term, language: language))
                            .font(DS.Typography.studyContext)
                            .foregroundStyle(DS.Color.textSecondary)
                            .lineLimit(3)
                        Button("Hide") { showsBookSentence = false }
                            .buttonStyle(.link)
                            .font(DS.Typography.caption)
                            .help("Write without the book's sentence")
                    }
                    .padding(.leading, DS.Spacing.sm)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(DS.Color.violet.opacity(0.35)).frame(width: 3)
                    }
                } else {
                    Button("Show the book's sentence") { showsBookSentence = true }
                        .buttonStyle(.link)
                        .font(DS.Typography.caption)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var editor: some View {
        TextField(
            String(localized: "Write a sentence with “\(word.term)”…"),
            text: $text,
            axis: .vertical
        )
        .textFieldStyle(.plain)
        .font(DS.Typography.studyContext)
        .lineLimit(2...5)
        .padding(DS.Spacing.sm)
        .background(DS.Color.surfaceInset, in: RoundedRectangle(cornerRadius: DS.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md)
            .strokeBorder(fieldFocused ? DS.Color.accent : DS.Color.hairlineStrong, lineWidth: fieldFocused ? 1.5 : 1))
        .focused($fieldFocused)
        .disabled(isChecking)
        .accessibilityLabel(Text("Your sentence with \(word.term)"))
    }

    private func result(_ feedback: SentenceWriting.Feedback) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            verdictChip(feedback.verdict)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(feedback.verdict == .natural ? "YOUR SENTENCE" : "YOUR SENTENCE, CORRECTED").dsOverlineLabel()
                Text(WordDiff.attributed(WordDiff.diff(written, feedback.corrected)))
                    .font(DS.Typography.studyContext)
                    .lineSpacing(3)
                    .textSelection(.enabled)
            }

            Label {
                Text(feedback.why)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lightbulb.fill").foregroundStyle(DS.Color.amber)
            }
            .font(DS.Typography.callout)
            .foregroundStyle(DS.Color.textPrimary)
            .padding(DS.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Color.surfaceInset, in: RoundedRectangle(cornerRadius: DS.Radius.md))

            if !feedback.example.isEmpty {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("A NATURAL EXAMPLE").dsOverlineLabel()
                    HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
                        Text(WordPageModel.emphasized(feedback.example, term: word.term, language: language))
                            .font(DS.Typography.studyContext)
                            .foregroundStyle(DS.Color.textPrimary)
                            .textSelection(.enabled)
                        SpeakButton(text: feedback.example, size: 13, language: language, tint: DS.Color.accent)
                    }
                }
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func verdictTitle(_ verdict: SentenceWriting.Verdict) -> String {
        switch verdict {
        case .natural:    return String(localized: "Natural")
        case .fixed:      return String(localized: "Corrected")
        case .otherSense: return String(localized: "Used in another sense")
        }
    }

    /// The verdict in words and a mark, not colour alone.
    private func verdictChip(_ verdict: SentenceWriting.Verdict) -> some View {
        let (symbol, tint): (String, Color) = switch verdict {
        case .natural:    ("checkmark", DS.Color.success)
        case .fixed:      ("pencil", DS.Color.warning)
        case .otherSense: ("arrow.triangle.branch", DS.Color.danger)
        }
        return Label(verdictTitle(verdict), systemImage: symbol)
            .font(DS.Typography.caption.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.xxs)
            .background(tint.opacity(0.14), in: Capsule())
    }

    @ViewBuilder
    private var buttons: some View {
        HStack(spacing: DS.Spacing.sm) {
            if isChecking {
                ProgressView().controlSize(.small)
                Text("Checking…")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textSecondary)
            }
            if let feedback {
                // Actions in a row are quiet; Next / Done is the step on.
                Button("Write Again") { writeAgain() }
                    .buttonStyle(.dsQuiet)
                    .help("Try another sentence with this word")
                Button(saved ? String(localized: "Saved") : String(localized: "Save Sentence")) { save(feedback) }
                    .buttonStyle(.dsQuiet)
                    .disabled(saved)
                    .help("Keep the corrected sentence as a sentence card")
                if let onNext {
                    Button("Next") { onNext() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Done") { onDone?() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            } else {
                if let onNext {
                    Button("Skip") { onNext() }
                        .buttonStyle(.dsQuiet)
                        .help("Next word without writing")
                }
                Button("Check") { check() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!SentenceWriting.isWorthChecking(text) || isChecking)
                    .help("⌘↩")
            }
        }
        .controlSize(.large)
    }

    // MARK: Actions

    private func reset() {
        task?.cancel()
        text = ""
        written = ""
        feedback = nil
        failure = nil
        isChecking = false
        saved = false
        DispatchQueue.main.async { fieldFocused = true }
    }

    private func writeAgain() {
        feedback = nil
        saved = false
        fieldFocused = true
    }

    private func check() {
        let sentence = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard SentenceWriting.isWorthChecking(sentence) else { return }
        isChecking = true
        failure = nil
        let target = language
        let user = SentenceWriting.userPrompt(word: word.term, sense: sense, bookSentence: word.sentence, sentence: sentence)
        task = Task {
            defer { isChecking = false }
            do {
                let raw = try await AppleOnDevice.chatWithFallback(
                    origin: .writing,
                    system: SentenceWriting.systemPrompt(target: target, native: Language.storedNative,
                                                         level: CEFRLevel.storedLearnerLevel),
                    user: user,
                    temperature: 0.2,
                    maxTokens: SentenceWriting.maxTokens
                )
                guard !Task.isCancelled else { return }
                if let parsed = SentenceWriting.parse(raw, written: sentence) {
                    written = sentence
                    feedback = parsed
                    onChecked(parsed)
                    Announcement.post(verdictTitle(parsed.verdict) + ". " + parsed.why)
                } else {
                    failure = String(localized: "The AI's answer couldn't be read. Try again.")
                }
            } catch {
                guard !Task.isCancelled else { return }
                failure = error.localizedDescription
            }
        }
    }

    private func save(_ feedback: SentenceWriting.Feedback) {
        let card = SavedWord(term: feedback.corrected, mode: ExplainMode.sentence.rawValue,
                             language: word.language ?? language.rawValue)
        store.add(card)
        saved = true
        onSaved()
        if let quickLookup {
            Task { await SentenceTranslation.fill(wordID: card.id, store: store, quickLookup: quickLookup) }
        }
    }
}

extension WordDiff {
    /// Removed: struck through and red. Added: bold and green. The strike
    /// and the weight carry the meaning for readers who can't tell the colours.
    static func attributed(_ segments: [Segment]) -> AttributedString {
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
}
