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

    private var voice: VoiceOption {
        switch Language(rawValue: targetRaw) ?? .english {
        case .turkish: return .turkish
        default:       return .englishUS
        }
    }

    var body: some View {
        Button {
            SpeechManager.shared.speak(text, voice: voice, rate: Float(speechRate))
        } label: {
            Image(systemName: "speaker.wave.2")
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(DS.Color.textTertiary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Pronounce")
        .accessibilityLabel("Pronounce \(text)")
    }
}
