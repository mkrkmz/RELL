//
//  QuizView+Sentence.swift
//  Reader for Language Learner
//
//  The listen-understand card for a saved sentence (Roadmap v19 Sprint 2,
//  approved mockup): it's read aloud first with the text blurred; T shows
//  the text, Space the translation; then the usual four ratings.
//

import SwiftUI

extension QuizView {
    @ViewBuilder
    func sentenceBody(_ word: SavedWord) -> some View {
        cardFace(content: sentenceFace(word), isFront: !session.isFlipped)
            .onAppear { speak(word) }
            .onChange(of: word.id) { _, _ in
                sentenceTextShown = false
                sentenceRepeating = false
                speak(word)
            }
            // v19 S5: VoiceOver sees it as something to press.
            .accessibilityAddTraits(.isButton)
            .onTapGesture {
                if !sentenceTextShown {
                    withAnimation(DS.Animation.standard) { sentenceTextShown = true }
                } else if !session.isFlipped {
                    flipCard()
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(session.isFlipped || sentenceTextShown ? Text(word.term) : Text("Sentence, read aloud"))
            .accessibilityHint(Text("Press T for the text, Space for the translation"))
    }

    private func sentenceFace(_ word: SavedWord) -> some View {
        VStack(spacing: DS.Spacing.md) {
            Button { speak(word) } label: {
                Image(systemName: "play.fill")
                    .font(DS.Typography.icon(session.isFlipped || sentenceTextShown ? 14 : 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: session.isFlipped || sentenceTextShown ? 38 : 54,
                           height: session.isFlipped || sentenceTextShown ? 38 : 54)
                    .background(DS.Color.accent, in: Circle())
                    .shadow(color: DS.Color.accent.opacity(0.35), radius: 6, y: 3)
            }
            .buttonStyle(.plain)
            .help("Listen again (S)")
            .accessibilityLabel("Listen again")

            Text(SentenceWords.marked(word.term, store: store, language: word.language.flatMap(Language.init)))
                .font(DS.Typography.studyContext)
                .foregroundStyle(DS.Color.textPrimary)
                .multilineTextAlignment(.center)
                .blur(radius: session.isFlipped || sentenceTextShown ? 0 : 6)
                .textSelection(.enabled)

            if session.isFlipped {
                Divider()
                if let translation = word.translation {
                    Text(translation)
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Color.textSecondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("No translation saved yet. The sentence's page can translate it.")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                }
                if let source = word.pdfFilename {
                    Text(BookIdentity.displayTitle(source) + (word.pageNumber.map { " · " + String(localized: "p. \($0)") } ?? ""))
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                }
                sentenceRepetition(word)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// v19 S4: say the sentence back (R) — practice; the 1–4 below still grade.
    @ViewBuilder
    private func sentenceRepetition(_ word: SavedWord) -> some View {
        if canRepeat(word) {
            Divider()
            if sentenceRepeating {
                SpokenRepetitionView(
                    sentence: word.term,
                    language: voiceLanguage(for: word),
                    start: .listening,
                    onResult: { store.recordSpokenRepetition($0, for: word.id) },
                    onClose: { sentenceRepeating = false }
                )
            } else {
                Button { sentenceRepeating = true } label: {
                    Label("Say It Aloud", systemImage: "mic")
                }
                .controlSize(.small)
                .help("Repeat the sentence aloud (R)")
            }
        }
    }

    func canRepeat(_ word: SavedWord) -> Bool {
        word.isSentence && session.isFlipped && SpokenRepetitionRecognizer.isOffered(for: voiceLanguage(for: word))
    }
}
