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

    @AppStorage("speechRate") private var speechRate: Double = 0.5
    @AppStorage(Language.targetLanguageKey) private var targetRaw = Language.defaultTarget.rawValue

    private var language: Language { Language(rawValue: targetRaw) ?? .english }

    var body: some View {
        Button {
            SpeechManager.shared.speak(text, language: language, rate: Float(speechRate))
        } label: {
            Image(systemName: "speaker.wave.2")
                .font(DS.Typography.icon(size, weight: .medium))
                .foregroundStyle(DS.Color.textTertiary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Pronounce")
        .accessibilityLabel("Pronounce \(text)")
    }
}
