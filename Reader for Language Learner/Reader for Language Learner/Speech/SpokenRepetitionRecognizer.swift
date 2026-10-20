//
//  SpokenRepetitionRecognizer.swift
//  Reader for Language Learner
//
//  Listens while the reader repeats a sentence (Roadmap v19 Sprint 4): the
//  microphone opens only on request, speech is recognised on this Mac only
//  (`requiresOnDeviceRecognition`) and the sound is never kept — buffers go
//  straight to the recogniser and are dropped. Listening stops after a
//  pause once speech has begun, after a while with nothing heard, and in
//  any case after twenty seconds.
//

import AVFoundation
import Speech

@MainActor
@Observable
final class SpokenRepetitionRecognizer {
    /// Off the main actor: on macOS 15 a main-actor deinit run outside a
    /// task crashes when it releases another one (v16 S0, CI crash reports).
    nonisolated deinit {}

    enum Phase: Equatable {
        case idle
        case listening
        /// `transcript` is what was heard.
        case finished
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// What has been heard so far — live while listening.
    private(set) var transcript = ""
    /// The microphone's level, 0…1, for the meter.
    private(set) var level: Float = 0

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var watch: Task<Void, Never>?
    @ObservationIgnored private var startedAt = Date()
    @ObservationIgnored private var lastHeardAt: Date?
    @ObservationIgnored private var ending = false
    @ObservationIgnored private lazy var box = RecognizerBox(self)

    // MARK: Access

    nonisolated enum Access: Equatable, Sendable { case granted, notDetermined, denied }

    /// Both the microphone and speech recognition.
    static var access: Access {
        let speech = SFSpeechRecognizer.authorizationStatus()
        let microphone = AVCaptureDevice.authorizationStatus(for: .audio)
        if speech == .denied || speech == .restricted || microphone == .denied || microphone == .restricted {
            return .denied
        }
        return speech == .authorized && microphone == .authorized ? .granted : .notDetermined
    }

    /// Asks macOS for both, speech recognition first. True when both granted.
    static func requestAccess() async -> Bool {
        let speech = await requestSpeechAuthorization()
        guard speech == .authorized else { return false }
        return await AVCaptureDevice.requestAccess(for: .audio)
    }

    nonisolated private static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }

    // MARK: Languages

    nonisolated enum Availability: Equatable, Sendable { case ready, noOnDeviceModel, unsupported }

    private static var availabilityCache: [Language: Availability] = [:]

    /// A recogniser for `language` that works on this Mac: its own locale,
    /// or another of the same language (en-US for English).
    static func recognizer(for language: Language) -> SFSpeechRecognizer? {
        let code = language.speechCode
        if let exact = SFSpeechRecognizer(locale: Locale(identifier: code)), exact.supportsOnDeviceRecognition {
            return exact
        }
        let prefix = String(code.prefix(2))
        for locale in SFSpeechRecognizer.supportedLocales().sorted(by: { $0.identifier < $1.identifier })
        where locale.identifier.hasPrefix(prefix) {
            if let recognizer = SFSpeechRecognizer(locale: locale), recognizer.supportsOnDeviceRecognition {
                return recognizer
            }
        }
        return nil
    }

    static func availability(for language: Language) -> Availability {
        if let cached = availabilityCache[language] { return cached }
        let prefix = String(language.speechCode.prefix(2))
        let result: Availability = recognizer(for: language) != nil ? .ready
            : SFSpeechRecognizer.supportedLocales().contains { $0.identifier.hasPrefix(prefix) } ? .noOnDeviceModel
            : .unsupported
        availabilityCache[language] = result
        return result
    }

    /// Whether the microphone button shows for `language` (approved: hidden
    /// when it can't work, the reason in Settings).
    static func isOffered(for language: Language) -> Bool {
        SpokenRepetition.offers(
            enabled: UserDefaults.standard.object(forKey: StorageKey.spokenRepetitionEnabled) as? Bool ?? true,
            availability: availability(for: language),
            access: access
        )
    }

    // MARK: Listening

    /// Recognised on this Mac only — the sound never leaves it.
    static func makeRequest() -> SFSpeechAudioBufferRecognitionRequest {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        return request
    }

    func start(language: Language) {
        cancel()
        transcript = ""
        level = 0
        guard let recognizer = Self.recognizer(for: language), recognizer.isAvailable else {
            phase = .failed(String(localized: "Speech recognition for this language isn't available on this Mac."))
            return
        }
        let request = Self.makeRequest()

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            phase = .failed(String(localized: "No microphone was found."))
            return
        }
        let sink = AudioSink(request: request, box: box)
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: sink.receive)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            phase = .failed(String(localized: "The microphone couldn't start: \(error.localizedDescription)"))
            return
        }

        self.engine = engine
        self.request = request
        task = recognizer.recognitionTask(with: request, resultHandler: RecognizerBox.handler(box))
        startedAt = Date()
        lastHeardAt = nil
        ending = false
        phase = .listening
        watch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                self?.checkSilence()
            }
        }
    }

    /// Stops listening and keeps what was heard.
    func stop() {
        guard phase == .listening, !ending else { return }
        ending = true
        stopAudio()
        request?.endAudio()
        // The final result usually follows at once; don't wait on it long.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            self?.finish()
        }
    }

    /// Stops without a result.
    func cancel() {
        stopAudio()
        task?.cancel()
        task = nil
        request = nil
        watch?.cancel()
        watch = nil
        ending = false
        if phase == .listening { phase = .idle }
    }

    func reset() {
        cancel()
        phase = .idle
        transcript = ""
    }

    private func stopAudio() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        level = 0
    }

    private func checkSilence() {
        guard phase == .listening, !ending else { return }
        let now = Date()
        if now.timeIntervalSince(startedAt) >= SpokenRepetition.maximumListening {
            stop()
        } else if let lastHeardAt {
            if now.timeIntervalSince(lastHeardAt) >= SpokenRepetition.silenceAfterSpeech { stop() }
        } else if now.timeIntervalSince(startedAt) >= SpokenRepetition.silenceBeforeSpeech {
            cancel()
            phase = .failed(String(localized: "I couldn't hear you. Check the microphone and try again."))
        }
    }

    private func finish() {
        guard phase == .listening else { return }
        task?.cancel()
        task = nil
        request = nil
        watch?.cancel()
        watch = nil
        ending = false
        phase = transcript.isEmpty
            ? .failed(String(localized: "I couldn't hear you. Check the microphone and try again."))
            : .finished
    }

    // MARK: From the audio and recognition threads

    fileprivate func heard(_ text: String?, isFinal: Bool, failed: Bool) {
        guard phase == .listening else { return }
        if let text, !text.isEmpty, text != transcript {
            transcript = text
            lastHeardAt = Date()
        }
        if isFinal || (failed && ending) {
            finish()
        } else if failed, transcript.isEmpty, !ending {
            cancel()
            phase = .failed(String(localized: "Speech recognition stopped. Try again."))
        }
    }

    fileprivate func setLevel(_ value: Float) {
        guard phase == .listening else { return }
        level = value
    }
}

/// A weak handle the audio and recognition callbacks reach the recogniser
/// through, back on the main actor.
nonisolated private final class RecognizerBox: @unchecked Sendable {
    weak var recognizer: SpokenRepetitionRecognizer?

    @MainActor init(_ recognizer: SpokenRepetitionRecognizer) {
        self.recognizer = recognizer
    }

    /// Built here, off the main actor, so the callback isn't main-actor
    /// isolated — Speech calls it on its own queue.
    static func handler(_ box: RecognizerBox) -> (SFSpeechRecognitionResult?, (any Error)?) -> Void {
        { result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in box.recognizer?.heard(text, isFinal: isFinal, failed: failed) }
        }
    }
}

/// Feeds microphone buffers to the recogniser and measures their level.
/// Nothing is stored: each buffer is appended and let go.
nonisolated private final class AudioSink: @unchecked Sendable {
    private let request: SFSpeechAudioBufferRecognitionRequest
    private let box: RecognizerBox
    private var lastLevelAt: TimeInterval = 0

    init(request: SFSpeechAudioBufferRecognitionRequest, box: RecognizerBox) {
        self.request = request
        self.box = box
    }

    func receive(_ buffer: AVAudioPCMBuffer, _ time: AVAudioTime) {
        request.append(buffer)
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastLevelAt > 0.08, let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
        lastLevelAt = now
        var sum: Float = 0
        for index in 0..<Int(buffer.frameLength) { sum += samples[index] * samples[index] }
        let rms = (sum / Float(buffer.frameLength)).squareRoot()
        let level = min(1, max(0, rms * 12))
        let box = box
        Task { @MainActor in box.recognizer?.setLevel(level) }
    }
}
