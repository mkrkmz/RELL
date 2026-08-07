//
//  SpeakButton.swift
//  Reader for Language Learner
//
//  Small reusable pronounce button. Speaks the given text with the voice
//  matching the user's target (learning) language and stored speech rate.
//

import SwiftUI

struct SpeakButton: View {
    let text: String
    var size: CGFloat = 12
    /// Voice language. Defaults to the study language; pass a word's own
    /// `SavedWord.language` so a multi-language library pronounces each word in
    /// the language it was actually saved from.
    var language: Language? = nil
    var tint: SwiftUI.Color = DS.Color.textTertiary

    @AppStorage("speechRate") private var speechRate: Double = 0.5
    @AppStorage(Language.targetLanguageKey) private var targetRaw = Language.defaultTarget.rawValue

    private var spokenLanguage: Language {
        language ?? Language(rawValue: targetRaw) ?? .english
    }

    var body: some View {
        Button {
            SpeechManager.shared.speak(text, language: spokenLanguage, rate: Float(speechRate))
        } label: {
            Image(systemName: "speaker.wave.2")
                .font(DS.Typography.icon(size, weight: .medium))
                .foregroundStyle(tint)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Pronounce")
        .accessibilityLabel("Pronounce \(text)")
    }
}
