//
//  SpokenRepetitionView.swift
//  Reader for Language Learner
//
//  "Say it back" (Roadmap v19 Sprint 4, approved mockup): read aloud, then
//  listen, then the sentence word by word — said (green, ✓), missed (grey,
//  struck through), heard as something else (red, dotted, with what was
//  heard under it). The mark and the style carry the meaning, not colour
//  alone. The first time, RELL says what the microphone is for before
//  macOS asks. In the reader's bottom lane, on a flipped sentence card in
//  the study room, and on a saved sentence's page.
//

import SwiftUI

struct SpokenRepetitionView: View {
    enum Start { case reading, listening }

    let sentence: String
    let language: Language
    /// Read the sentence first (the reader), or listen at once (a study
    /// card that has just been heard).
    var start: Start = .reading
    var onResult: (SpokenRepetition.Result) -> Void = { _ in }
    var onClose: (() -> Void)?

    private enum Step: Equatable {
        case explaining, denied, reading, listening, result(SpokenRepetition.Result), failed(String)
    }

    @State private var step: Step = .reading
    @State private var recognizer = SpokenRepetitionRecognizer()
    @State private var slower = false
    @AppStorage(StorageKey.spokenRepetitionAutoListen) private var autoListen = true
    @AppStorage(StorageKey.spokenRepetitionExplained) private var explained = false
    @AppStorage(StorageKey.spokenRepetitionHomophoneNoted) private var homophoneNoted = false
    @AppStorage(StorageKey.speechRate) private var speechRate: Double = 0.5
    @State private var showsHomophoneNote = false

    private var speech: SpeechManager { SpeechManager.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            switch step {
            case .explaining: explainer
            case .denied:     deniedNote
            case .reading:    readingRow
            case .listening:  listeningRow
            case .result(let result): resultView(result)
            case .failed(let message): failedRow(message)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear(perform: begin)
        .onChange(of: sentence) { _, _ in begin() }
        .onDisappear {
            recognizer.cancel()
            if step == .reading { speech.stop() }
        }
        .onChange(of: speech.state) { old, new in
            // The sentence has been read: the microphone opens (approved 1).
            if step == .reading, old != .idle, new == .idle, autoListen { listen() }
        }
        .onChange(of: recognizer.phase) { _, phase in
            switch phase {
            case .finished:
                let result = SpokenRepetition.compare(sentence: sentence, heard: recognizer.transcript)
                if !homophoneNoted, result.words.contains(where: { if case .different = $0.kind { true } else { false } }) {
                    showsHomophoneNote = true
                    homophoneNoted = true
                }
                step = .result(result)
                onResult(result)
                Announcement.post(accessibilitySummary(result))
            case .failed(let message):
                step = .failed(message)
            case .idle, .listening:
                break
            }
        }
        .onKeyPress(.escape) {
            guard step == .listening else { return .ignored }
            recognizer.stop()
            return .handled
        }
    }

    // MARK: Steps

    private func begin() {
        recognizer.reset()
        switch SpokenRepetitionRecognizer.access {
        case .denied:
            step = .denied
        case .notDetermined where !explained:
            step = .explaining
        case .notDetermined:
            requestThenStart()
        case .granted:
            start == .reading ? read() : listen()
        }
    }

    private func read() {
        recognizer.cancel()
        step = .reading
        let rate = Float(slower ? speechRate * 0.75 : speechRate)
        speech.speak(sentence, language: language, rate: rate)
    }

    private func listen() {
        speech.stop()
        step = .listening
        recognizer.start(language: language)
    }

    private func requestThenStart() {
        explained = true
        Task {
            if await SpokenRepetitionRecognizer.requestAccess() {
                start == .reading ? read() : listen()
            } else {
                step = .denied
            }
        }
    }

    // MARK: Views

    private var explainer: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Label("The microphone, for repeating aloud", systemImage: "mic")
                .font(DS.Typography.callout.weight(.semibold))
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text("• The microphone listens only while 🎙 is on.")
                Text("• What you say is recognised on this Mac. Nothing is recorded or sent.")
                Text("• Only how many words matched is kept.")
            }
            .font(DS.Typography.caption)
            .foregroundStyle(DS.Color.textSecondary)
            Text("macOS will then ask twice: for the microphone and for speech recognition.")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.textTertiary)
            HStack {
                Spacer()
                Button("Not Now") { onClose?() }
                Button("Continue") { requestThenStart() }
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
        }
    }

    private var deniedNote: some View {
        HStack(spacing: DS.Spacing.sm) {
            Label("Microphone or speech recognition is turned off for RELL.", systemImage: "mic.slash")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.warning)
            Spacer(minLength: DS.Spacing.sm)
            Button("Open System Settings") { SpokenRepetitionSettings.openMicrophonePrivacy() }
                .controlSize(.small)
            closeButton
        }
    }

    private var readingRow: some View {
        HStack(spacing: DS.Spacing.sm) {
            circle(symbol: "speaker.wave.2.fill", tint: DS.Color.accent, ring: false)
            Text(speech.state == .idle && !autoListen ? "Press 🎙 when you're ready" : "Listen…")
                .font(DS.Typography.callout.weight(.semibold))
            Spacer(minLength: DS.Spacing.sm)
            Button { listen() } label: { Label("Say It", systemImage: "mic.fill") }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("Start listening now")
            closeButton
        }
    }

    private var listeningRow: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.sm) {
                circle(symbol: "mic.fill", tint: DS.Color.danger, ring: true)
                LevelMeter(level: recognizer.level)
                Text("Listening…")
                    .font(DS.Typography.callout.weight(.semibold))
                Spacer(minLength: DS.Spacing.sm)
                Button("Stop") { recognizer.stop() }
                    .controlSize(.small)
                    .help("Esc")
            }
            Text(recognizer.transcript.isEmpty ? " " : recognizer.transcript)
                .font(DS.Typography.callout)
                .fontDesign(.serif)
                .italic()
                .foregroundStyle(DS.Color.textSecondary)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Listening"))
    }

    private func resultView(_ result: SpokenRepetition.Result) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                scorePill(result)
                Spacer(minLength: DS.Spacing.sm)
                Button { slower = false; read() } label: { Label("Listen", systemImage: "speaker.wave.2") }
                Button { slower = true; read() } label: { Label("Slower", systemImage: "tortoise") }
                    .help("Read at three-quarter speed")
                Button { listen() } label: { Label("Say It Again", systemImage: "mic.fill") }
                    .buttonStyle(.borderedProminent)
                closeButton
            }
            .controlSize(.small)

            FlowLayout(spacing: DS.Spacing.xs) {
                ForEach(Array(result.words.enumerated()), id: \.offset) { _, word in
                    wordView(word)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(accessibilitySummary(result)))

            if showsHomophoneNote {
                Label("Words that sound alike — read and red — can be heard as each other. That's the recogniser, not always you.",
                      systemImage: "info.circle")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func failedRow(_ message: String) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.warning)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: DS.Spacing.sm)
            Button("Try Again") { listen() }
                .controlSize(.small)
            closeButton
        }
    }

    @ViewBuilder
    private var closeButton: some View {
        if let onClose {
            Button { onClose() } label: { Image(systemName: "xmark") }
                .buttonStyle(.dsIcon)
                .help("Close")
                .accessibilityLabel("Close")
        }
    }

    private func circle(symbol: String, tint: Color, ring: Bool) -> some View {
        Image(systemName: symbol)
            .font(DS.Typography.icon(13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(tint, in: Circle())
            .overlay(Circle().strokeBorder(tint.opacity(ring ? 0.25 : 0), lineWidth: 5).padding(-5))
            .accessibilityHidden(true)
    }

    private func scorePill(_ result: SpokenRepetition.Result) -> some View {
        let tint = result.isPerfect ? DS.Color.success : DS.Color.warning
        let text = result.isPerfect
            ? String(localized: "\(result.said) of \(result.total) words · Spot on")
            : String(localized: "\(result.said) of \(result.total) words")
        return Label(text, systemImage: result.isPerfect ? "checkmark" : "circle.lefthalf.filled")
            .font(DS.Typography.caption.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.hairline)
            .background(tint.opacity(0.14), in: Capsule())
            .fixedSize()
    }

    @ViewBuilder
    private func wordView(_ word: SpokenRepetition.Word) -> some View {
        switch word.kind {
        case .said:
            Text(word.text)
                .font(DS.Typography.body)
                .fontDesign(.serif)
                .foregroundStyle(DS.Color.success)
        case .missed:
            Text(word.text)
                .font(DS.Typography.body)
                .fontDesign(.serif)
                .strikethrough()
                .foregroundStyle(DS.Color.textTertiary)
        case .different(let heard):
            VStack(spacing: 0) {
                Text(word.text)
                    .font(DS.Typography.body)
                    .fontDesign(.serif)
                    .underline(pattern: .dot, color: DS.Color.danger)
                    .foregroundStyle(DS.Color.danger)
                Text("“\(heard)”")
                    .font(DS.Typography.caption2)
                    .foregroundStyle(DS.Color.danger)
            }
        }
    }

    private func accessibilitySummary(_ result: SpokenRepetition.Result) -> String {
        let hard = result.hardWords
        let head = String(localized: "\(result.said) of \(result.total) words")
        return hard.isEmpty ? head : head + ". " + String(localized: "Not heard right: \(hard.joined(separator: ", "))")
    }
}

/// The microphone's level in five bars.
private struct LevelMeter: View {
    let level: Float

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                let threshold = Float(index) / 5
                Capsule()
                    .fill(DS.Color.danger.opacity(level > threshold ? 1 : 0.25))
                    .frame(width: 3, height: 6 + CGFloat(index % 3) * 5)
            }
        }
        .frame(height: 18)
        .accessibilityHidden(true)
    }
}

/// Settings ▸ Speech links (approved: the reason and the way to fix it).
enum SpokenRepetitionSettings {
    static func openMicrophonePrivacy() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openDictation() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
