//
//  ContentView+Repeat.swift
//  Reader for Language Learner
//
//  Repeating a sentence aloud in the reader (Roadmap v19 Sprint 4,
//  approved mockup): from the selection bar's microphone, the right-click
//  menu or Speech ▸ Repeat Selection Aloud (⌃⌘R), in the page's bottom
//  lane under the translation strip. A saved sentence keeps its last
//  result; any other selection keeps nothing.
//

import SwiftUI

extension ContentView {

    func withSpokenRepetition(_ content: some View) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .repeatAloudCommand)) { note in
                // Every window hears it; the one the reader is in answers.
                guard model.hostWindow?.isKeyWindow == true else { return }
                let text = ((note.object as? String) ?? selectionState.selectedText)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard SpokenRepetition.isEligible(text),
                      SpokenRepetitionRecognizer.isOffered(for: Language.storedTarget)
                else { return }
                speechManager.stop()
                model.repeatSentence = text
            }
            .onChange(of: selectionState.documentURL) { _, _ in model.repeatSentence = nil }
    }

    @ViewBuilder
    var repeatLane: some View {
        if let sentence = model.repeatSentence, !chromeHidden {
            SpokenRepetitionView(
                sentence: sentence,
                language: Language.storedTarget,
                onResult: { result in
                    if let saved = savedWordsStore.savedSentence(matching: sentence) {
                        savedWordsStore.recordSpokenRepetition(result, for: saved.id)
                    }
                },
                onClose: { model.repeatSentence = nil }
            )
            .padding(DS.Spacing.sm)
            .dsReadingOverlay(RoundedRectangle(cornerRadius: DS.Radius.lg))
            .frame(maxWidth: 720)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.sm)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }
}
