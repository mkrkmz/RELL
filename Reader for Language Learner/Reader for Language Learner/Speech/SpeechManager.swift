//
//  SpeechManager.swift
//  Reader for Language Learner
//

import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class SpeechManager: NSObject {
    static let shared = SpeechManager()

    enum PlaybackState: Equatable {
        case idle
        case speaking
        case paused
    }

    private(set) var state: PlaybackState = .idle
    /// 0...1 across the whole queued text, or nil while idle. Tracked across
    /// multiple queued utterances (see `speak`), not just the current one.
    private(set) var progress: Double?

    /// Shim for call sites that only care about the binary speaking/not.
    var isSpeaking: Bool { state != .idle }

    private let synthesizer = AVSpeechSynthesizer()
    /// Parallel to the utterances handed to the synthesizer, so `didStart`
    /// can look up how much text preceded the one that just began.
    private var utteranceOffsets: [ObjectIdentifier: Int] = [:]
    private var totalCharacterCount = 0

    // ── Queue state (enables mid-playback rate changes) ──────────────────
    /// The sentence-split queue of the current read, kept so a rate change can
    /// re-enqueue the remaining sentences at the new speed without losing the
    /// place. Cleared by `stop()`.
    private var sentences: [String] = []
    /// Utterance → its index in `sentences`, so `didStart` can track where we
    /// are for a mid-playback re-enqueue.
    private var sentenceIndexByUtterance: [ObjectIdentifier: Int] = [:]
    /// Index of the sentence currently being spoken — the resume point for a
    /// rate change.
    private var currentSentenceIndex = 0
    private var currentLanguage: Language = .english
    private var currentRate: Float = 0.5

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speaks `text` in `language`'s voice. Text beyond `limit` (nil = no
    /// cap, for whole-page reads) is dropped; the remainder is split into
    /// sentence-sized utterances — natural pause points, and each one's
    /// `willSpeakRangeOfSpeechString` callback contributes to `progress`
    /// instead of the sentence break stalling a single giant utterance.
    func speak(_ text: String, language: Language, rate: Float, limit: Int? = 500) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        stop()

        let capped: String
        if let limit, trimmed.count > limit {
            capped = String(trimmed.prefix(limit))
        } else {
            capped = trimmed
        }

        currentLanguage = language
        currentRate = max(0.35, min(0.65, rate))
        sentences = Self.sentenceSplit(capped)
        totalCharacterCount = capped.count
        currentSentenceIndex = 0

        enqueue(fromIndex: 0)
        progress = 0
        state = .speaking
    }

    /// Queues `sentences[startIndex...]` at the current rate/voice, rebuilding
    /// the offset bookkeeping so `progress` stays continuous across a rate
    /// change (offsets are absolute over the whole text, not the sub-queue).
    private func enqueue(fromIndex startIndex: Int) {
        utteranceOffsets.removeAll()
        sentenceIndexByUtterance.removeAll()
        guard startIndex < sentences.count else { return }

        let voice = preferredVoice(for: currentLanguage)
        var offset = sentences[0..<startIndex].reduce(0) { $0 + $1.count }
        for index in startIndex..<sentences.count {
            let sentence = sentences[index]
            let utterance = AVSpeechUtterance(string: sentence)
            utterance.rate = currentRate
            utterance.voice = voice
            let id = ObjectIdentifier(utterance)
            utteranceOffsets[id] = offset
            sentenceIndexByUtterance[id] = index
            offset += sentence.count
            synthesizer.speak(utterance)
        }
    }

    /// Applies a new speaking rate. If a read is in progress, the remaining
    /// sentences (from the one currently being spoken) are re-queued at the new
    /// speed — the current sentence restarts, everything after it follows. A
    /// no-op when idle beyond storing the rate for the next `speak`.
    func setRate(_ rate: Float) {
        let clamped = max(0.35, min(0.65, rate))
        guard clamped != currentRate else { return }
        currentRate = clamped

        guard state != .idle, !sentences.isEmpty else { return }
        let resumeIndex = currentSentenceIndex
        // Cancel the in-flight queue then immediately re-queue: because a new
        // utterance is enqueued synchronously, `synthesizer.isSpeaking` is true
        // again by the time the async `didCancel` runs, so it skips the reset
        // (same guard `didFinish` uses for queued utterances).
        synthesizer.stopSpeaking(at: .immediate)
        enqueue(fromIndex: resumeIndex)
        state = .speaking
    }

    /// Convenience for non-View call sites (`NSViewRepresentable`
    /// coordinators) that can't use `@AppStorage`: resolves the voice from
    /// the stored target language and reads the stored speech rate directly.
    func speakResolved(_ text: String, limit: Int? = 500) {
        let rate = UserDefaults.standard.object(forKey: "speechRate") as? Double ?? 0.5
        speak(text, language: Language.storedTarget, rate: Float(rate), limit: limit)
    }

    func pause() {
        guard state == .speaking else { return }
        synthesizer.pauseSpeaking(at: .word)
    }

    func resume() {
        guard state == .paused else { return }
        synthesizer.continueSpeaking()
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        utteranceOffsets.removeAll()
        sentenceIndexByUtterance.removeAll()
        sentences.removeAll()
        currentSentenceIndex = 0
        totalCharacterCount = 0
        state = .idle
        progress = nil
    }

    private func preferredVoice(for language: Language) -> AVSpeechSynthesisVoice? {
        let code = language.speechCode
        if let exact = AVSpeechSynthesisVoice(language: code) { return exact }
        let prefix = code.prefix(2) + "-"
        return AVSpeechSynthesisVoice.speechVoices().first { $0.language.hasPrefix(prefix) }
    }

    /// Splits on sentence boundaries via `enumerateSubstrings`; falls back to
    /// the whole string when it finds none (e.g. a bare word with no
    /// terminal punctuation — the common case for single saved words).
    /// Internal (not private) so tests can exercise it directly without
    /// triggering real speech synthesis.
    static func sentenceSplit(_ text: String) -> [String] {
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .bySentences) { substring, _, _, _ in
            if let sentence = substring?.trimmingCharacters(in: .whitespacesAndNewlines), !sentence.isEmpty {
                sentences.append(sentence)
            }
        }
        return sentences.isEmpty ? [text] : sentences
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SpeechManager: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in
            self.state = .speaking
            if let index = self.sentenceIndexByUtterance[id] {
                self.currentSentenceIndex = index
            }
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in
            guard self.totalCharacterCount > 0 else { return }
            let offset = self.utteranceOffsets[id] ?? 0
            let spoken = offset + characterRange.location + characterRange.length
            self.progress = min(1, Double(spoken) / Double(self.totalCharacterCount))
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        Task { @MainActor in self.state = .paused }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        Task { @MainActor in self.state = .speaking }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            // Queued utterances share one AVSpeechSynthesizer; the last one
            // finishing is what actually ends playback, but `isSpeaking` on
            // the synthesizer itself is authoritative for "any queued
            // utterance still pending" without tracking queue length here.
            guard !synthesizer.isSpeaking else { return }
            self.state = .idle
            self.progress = nil
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            // A mid-playback rate change cancels the queue and immediately
            // re-enqueues, so the synthesizer is speaking again here — only a
            // real stop (nothing queued) should reset state.
            guard !synthesizer.isSpeaking else { return }
            self.state = .idle
            self.progress = nil
        }
    }
}
