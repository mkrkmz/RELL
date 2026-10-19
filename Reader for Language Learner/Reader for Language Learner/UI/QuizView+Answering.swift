//
//  QuizView+Answering.swift
//  Reader for Language Learner
//
//  The answer cards: multiple choice, listening and typed recall. Split out
//  of QuizView.swift (v19 S0), unchanged.
//

import SwiftUI

extension QuizView {

    // MARK: - Multiple Choice Body (definition → term)

    @ViewBuilder
    func multipleChoiceBody(_ word: SavedWord) -> some View {
        VStack(spacing: DS.Spacing.md) {
            if session.mcOptions.count < 2 {
                // No usable definition or not enough distractor terms —
                // fall back to a plain flashcard-style reveal.
                if session.isFlipped {
                    cardFace(content: revealContent(for: word), isFront: false)
                } else {
                    cardFace(content: frontContent(for: word), isFront: true)
                    Button("Reveal answer") { revealAnswer() }
                        .buttonStyle(.bordered)
                }
            } else {
                if session.isFlipped {
                    cardFace(content: revealContent(for: word), isFront: false)
                } else {
                    cardFace(content: choiceQuestionContent(for: word), isFront: true)
                }

                VStack(spacing: DS.Spacing.sm) {
                    ForEach(Array(session.mcOptions.enumerated()), id: \.offset) { index, option in
                        choiceRow(index: index, option: option, correct: word.term)
                    }
                }
                .padding(.horizontal, DS.Spacing.md)
            }
        }
    }

    /// Question card: the definition with the term masked out. The term,
    /// mastery badge, and source badge are all withheld until reveal — each
    /// one leaks the answer.
    func choiceQuestionContent(for word: SavedWord) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("WHICH WORD FITS?")
                .font(DS.Typography.caption2.weight(.bold))
                .foregroundStyle(DS.Color.textTertiary)
            cardScroll(maxHeight: DS.Layout.cardBackHeightCompact) {
                Text(maskedDefinition(for: word))
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Color.textPrimary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func maskedDefinition(for word: SavedWord) -> String {
        QuizMatching.maskTerm(
            word.term,
            in: MarkdownUtils.sanitizeLLMOutput(word.reviewDefinition)
        )
    }

    func choiceRow(index: Int, option: String, correct: String) -> some View {
        let isCorrect = option == correct
        let isSelected = session.mcSelectedIndex == index
        let tint: Color = {
            guard session.isFlipped else { return DS.Color.hairlineStrong }
            if isCorrect { return DS.Color.success }
            if isSelected { return DS.Color.danger }
            return DS.Color.hairlineStrong
        }()

        return Button {
            guard !session.isFlipped else { return }
            session.mcSelectedIndex = index
            revealAnswer()
        } label: {
            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                Image(systemName: session.isFlipped && (isCorrect || isSelected)
                      ? (isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                      : "circle")
                    .foregroundStyle(session.isFlipped && (isCorrect || isSelected) ? tint : DS.Color.textTertiary)
                Text(option)
                    .font(DS.Typography.callout.weight(.medium))
                    .foregroundStyle(DS.Color.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(DS.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((session.isFlipped && (isCorrect || isSelected) ? tint.opacity(0.10) : DS.Color.surfaceElevated))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .strokeBorder(tint, lineWidth: session.isFlipped && (isCorrect || isSelected) ? 1.2 : 0.6)
            )
        }
        .buttonStyle(.plain)
        .disabled(session.isFlipped)
        .accessibilityLabel(choiceAccessibilityLabel(option: option, isCorrect: isCorrect, isSelected: isSelected))
    }

    func choiceAccessibilityLabel(option: String, isCorrect: Bool, isSelected: Bool) -> String {
        guard session.isFlipped else { return option }
        if isCorrect { return String(localized: "\(option), correct answer") }
        if isSelected { return String(localized: "\(option), your answer, incorrect") }
        return option
    }

    // MARK: - Listening Body (hear the word → type it)

    @ViewBuilder
    func listeningBody(_ word: SavedWord) -> some View {
        VStack(spacing: DS.Spacing.md) {
            if session.isFlipped {
                cardFace(content: revealContent(for: word), isFront: false)
                typedResultView(word)
            } else {
                cardFace(content: listeningQuestionContent(for: word), isFront: true)

                VStack(spacing: DS.Spacing.sm) {
                    TextField("Type what you hear…", text: $session.typedAnswer)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            if !session.typedAnswer.trimmingCharacters(in: .whitespaces).isEmpty {
                                revealAnswer()
                            }
                        }
                    Button("Check") { revealAnswer() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .disabled(session.typedAnswer.trimmingCharacters(in: .whitespaces).isEmpty)
                        .keyboardShortcut(.return, modifiers: [.command])
                }
                .padding(.horizontal, DS.Spacing.lg)
            }
        }
        // Say the word as the card appears, and again whenever the card changes.
        .onAppear { speak(word) }
        .onChange(of: word.id) { _, _ in speak(word) }
    }

    /// The question is the audio itself — a big replay button, no spelling.
    func listeningQuestionContent(for word: SavedWord) -> some View {
        VStack(spacing: DS.Spacing.md) {
            Text("LISTEN AND TYPE THE WORD")
                .font(DS.Typography.caption2.weight(.bold))
                .foregroundStyle(DS.Color.textTertiary)

            SpeakButton(
                text: word.term,
                size: 34,
                language: voiceLanguage(for: word),
                tint: DS.Color.accent
            )
            .padding(DS.Spacing.md)

            Text("Tap to hear it again")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    /// The word's own saved language, falling back to the study language for
    /// words saved before per-word language tracking (pre-v1.24).
    func voiceLanguage(for word: SavedWord) -> Language {
        word.language.flatMap(Language.init(rawValue:)) ?? Language.storedTarget
    }

    func speak(_ word: SavedWord) {
        let rate = UserDefaults.standard.object(forKey: StorageKey.speechRate) as? Double ?? 0.5
        SpeechManager.shared.speak(word.term, language: voiceLanguage(for: word), rate: Float(rate))
    }

    // MARK: - Typed Recall Body (cloze → type the word)

    @ViewBuilder
    func typedBody(_ word: SavedWord) -> some View {
        let hasQuestion = clozeSentence(for: word) != nil || word.usableDefinition != nil

        VStack(spacing: DS.Spacing.md) {
            if session.isFlipped {
                cardFace(content: revealContent(for: word), isFront: false)
            } else if hasQuestion {
                cardFace(content: typedQuestionContent(for: word), isFront: true)
            } else {
                cardFace(content: frontContent(for: word), isFront: true)
            }

            if !session.isFlipped {
                if hasQuestion {
                    VStack(spacing: DS.Spacing.sm) {
                        TextField("Type the word…", text: $session.typedAnswer)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { if !session.typedAnswer.trimmingCharacters(in: .whitespaces).isEmpty { revealAnswer() } }
                        Button("Check") { revealAnswer() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                            .disabled(session.typedAnswer.trimmingCharacters(in: .whitespaces).isEmpty)
                            .keyboardShortcut(.return, modifiers: [.command])
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                } else {
                    // Nothing to build a question from — plain reveal.
                    Button("Reveal answer") { revealAnswer() }
                        .buttonStyle(.bordered)
                }
            } else if hasQuestion {
                typedResultView(word)
            }
        }
    }

    /// Question card: the saved sentence as a cloze (term blanked out) plus
    /// the masked definition as a secondary hint.
    func typedQuestionContent(for word: SavedWord) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text(clozeSentence(for: word) != nil ? "TYPE THE MISSING WORD" : "TYPE THE WORD")
                .font(DS.Typography.caption2.weight(.bold))
                .foregroundStyle(DS.Color.textTertiary)

            cardScroll(maxHeight: DS.Layout.cardBackHeightCompact) {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    if let cloze = clozeChoice(for: word) {
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            Text("“\(cloze.masked)”")
                                .font(DS.Typography.body)
                                .italic()
                                .foregroundStyle(DS.Color.textPrimary)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                            // A sentence met again in reading says where from;
                            // the saved one is the card's usual context.
                            if let source = cloze.source {
                                Label(
                                    "\(source.documentTitle) · \(WordPageModel.locationLabel(source))",
                                    systemImage: source.isEPUB ? "book" : "doc.text"
                                )
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Color.textTertiary)
                                .lineLimit(1)
                            }
                        }
                    }

                    if let definition = word.usableDefinition {
                        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                            Text("HINT")
                                .font(DS.Typography.caption2.weight(.bold))
                                .foregroundStyle(DS.Color.textTertiary)
                            Text(QuizMatching.maskTerm(word.term, in: definition))
                                .font(DS.Typography.callout)
                                .foregroundStyle(DS.Color.textSecondary)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Objective ✓/✗ result shown under the reveal card.
    func typedResultView(_ word: SavedWord) -> some View {
        let isCorrect = QuizMatching.matchesTerm(typed: session.typedAnswer, term: word.term)
        let tint = isCorrect ? DS.Color.success : DS.Color.danger
        let trimmedAnswer = session.typedAnswer.trimmingCharacters(in: .whitespaces)

        return HStack(spacing: DS.Spacing.sm) {
            Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(tint)
            Text(isCorrect ? "Correct!" : "Not quite")
                .font(DS.Typography.caption.weight(.semibold))
                .foregroundStyle(tint)
            if !isCorrect, !trimmedAnswer.isEmpty {
                Text("— you wrote “\(trimmedAnswer)”")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textSecondary)
                    .italic()
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Spacing.md)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        .padding(.horizontal, DS.Spacing.md)
    }

    /// The card's sentence with the term masked — the saved one or one met
    /// since in reading, rotating by review — or nil when none contains the
    /// term (no blank → not a cloze).
    func clozeChoice(for word: SavedWord) -> ClozeContext.Choice? {
        ClozeContext.choice(
            for: word,
            encounters: encounterStore?.encounters(for: word.id) ?? [],
            unfamiliar: Set(store.words
                .filter { $0.id != word.id && $0.masteryLevel != .mastered }
                .map { $0.term.lowercased() })
        )
    }

    func clozeSentence(for word: SavedWord) -> String? {
        clozeChoice(for: word)?.masked
    }
}
