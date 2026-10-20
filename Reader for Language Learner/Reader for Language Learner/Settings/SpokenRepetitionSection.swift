//
//  SpokenRepetitionSection.swift
//  Reader for Language Learner
//
//  Settings ▸ Reading ▸ Repeating Aloud (Roadmap v19 Sprint 4, approved
//  mockup): on or off, whether the microphone opens once the sentence has
//  been read, and why it may not show — access refused, or no on-device
//  recognition for the language you're learning — with the way to fix it.
//

import SwiftUI

struct SpokenRepetitionSection: View {
    @AppStorage(StorageKey.spokenRepetitionEnabled) private var enabled = true
    @AppStorage(StorageKey.spokenRepetitionAutoListen) private var autoListen = true
    @AppStorage(Language.targetLanguageKey) private var targetRaw = Language.defaultTarget.rawValue

    private var target: Language { Language(rawValue: targetRaw) ?? .english }

    var body: some View {
        Section {
            Toggle(isOn: $enabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Repeat Aloud")
                    Text("Hear a sentence, say it back, see which words matched.")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                }
            }
            Toggle(isOn: $autoListen) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Listen Once the Sentence Is Read")
                    Text("Off: press the microphone when you're ready.")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                }
            }
            .disabled(!enabled)

            accessRow
            languageRow
        } header: {
            Text("Repeating Aloud")
        } footer: {
            Text("Speech is recognised on this Mac. Nothing is recorded or sent; a saved sentence keeps only how many words matched.")
                .foregroundStyle(DS.Color.textTertiary)
        }
    }

    @ViewBuilder
    private var accessRow: some View {
        switch SpokenRepetitionRecognizer.access {
        case .granted:
            LabeledContent("Microphone") { Label("Allowed", systemImage: "checkmark").foregroundStyle(DS.Color.success) }
        case .notDetermined:
            LabeledContent("Microphone") {
                Text("Asked the first time you repeat a sentence")
                    .foregroundStyle(DS.Color.textTertiary)
            }
        case .denied:
            LabeledContent {
                Button("Open System Settings") { SpokenRepetitionSettings.openMicrophonePrivacy() }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Microphone")
                    Text("Turned off for RELL in Privacy & Security, so the microphone button is hidden.")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.warning)
                }
            }
        }
    }

    @ViewBuilder
    private var languageRow: some View {
        switch SpokenRepetitionRecognizer.availability(for: target) {
        case .ready:
            LabeledContent("\(target.nativeName) (on this Mac)") {
                Label("Ready", systemImage: "checkmark").foregroundStyle(DS.Color.success)
            }
        case .noOnDeviceModel:
            LabeledContent {
                Button("Open System Settings") { SpokenRepetitionSettings.openDictation() }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(target.nativeName)
                    Text("No on-device recognition for this language yet. Add it under Keyboard ▸ Dictation and it turns on.")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.warning)
                }
            }
        case .unsupported:
            LabeledContent(target.nativeName) {
                Text("Not supported on this Mac")
                    .foregroundStyle(DS.Color.textTertiary)
            }
        }
    }
}
