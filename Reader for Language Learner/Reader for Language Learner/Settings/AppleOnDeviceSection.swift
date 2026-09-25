//
//  AppleOnDeviceSection.swift
//  Reader for Language Learner
//
//  Settings ▸ AI: the Apple on-device layer. It answers the modules it's
//  reliable for; the provider configured below handles the rest.
//

import SwiftUI

struct AppleOnDeviceSection: View {
    @AppStorage(AppleOnDevice.enabledKey) private var enabled = true
    @AppStorage(Language.nativeLanguageKey) private var nativeRaw = Language.defaultNative.rawValue
    @AppStorage(Language.targetLanguageKey) private var targetRaw = Language.defaultTarget.rawValue

    var body: some View {
        // Re-read on language changes: support is per language.
        let reason = AppleOnDevice.unavailableReason
        let _ = (nativeRaw, targetRaw)
        Section {
            Toggle(isOn: $enabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple On-Device Model")
                    Text("Answers on this Mac — no setup, no internet, no cost.")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                }
            }
            .disabled(reason != nil)

            if let reason {
                Label(reason, systemImage: "info.circle")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
            }
        } header: {
            Text("On-Device")
        } footer: {
            Text("Used for definitions, meanings, examples, synonyms, usage notes, Ask AI and word levels. Pronunciation, etymology, mnemonics, collocations and word family always use the provider below — the on-device model gets them wrong too often.")
                .foregroundStyle(DS.Color.textTertiary)
        }
    }
}
