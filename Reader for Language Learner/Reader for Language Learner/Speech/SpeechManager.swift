//
//  SpeechManager.swift
//  Reader for Language Learner
//

import AVFoundation
import Foundation
import Observation

enum VoiceOption: String, CaseIterable, Identifiable {
    case englishUS = "English (US)"
    case englishUK = "English (UK)"
    case turkish   = "Turkish"

    var id: String { rawValue }

    var languageCode: String {
        switch self {
        case .englishUS: return "en-US"
        case .englishUK: return "en-GB"
        case .turkish:   return "tr-TR"
        }
    }
}

@MainActor
@Observable
final class SpeechManager: NSObject {
    static let shared = SpeechManager()

    private(set) var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, voice: VoiceOption, rate: Float) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }

        let cappedText = trimmed.count > 500 ? String(trimmed.prefix(500)) : trimmed
        let utterance  = AVSpeechUtterance(string: cappedText)
        utterance.rate  = max(0.35, min(0.65, rate))
        utterance.voice = preferredVoice(for: voice)
        synthesizer.speak(utterance)
        isSpeaking = true
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    private func preferredVoice(for option: VoiceOption) -> AVSpeechSynthesisVoice? {
        if let exact = AVSpeechSynthesisVoice(language: option.languageCode) { return exact }
        let prefix = option.languageCode.prefix(2) + "-"
        return AVSpeechSynthesisVoice.speechVoices().first { $0.language.hasPrefix(prefix) }
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SpeechManager: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = true }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}
