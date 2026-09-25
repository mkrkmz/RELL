//
//  PrivacySummarySection.swift
//  Reader for Language Learner
//
//  Settings ▸ AI: where each feature's text goes right now — this Mac, or
//  which server. Follows the live routing (Apple's layer, the configured
//  provider, the translation engine), so it can't drift from the code.
//

import SwiftUI

struct PrivacySummarySection: View {
    @AppStorage(AppleOnDevice.enabledKey) private var appleEnabled = true
    @AppStorage(LLMConfiguration.providerTypeKey) private var providerTypeRaw = LLMConfiguration.defaultProviderType.rawValue
    @AppStorage(LLMConfiguration.serverURLKey) private var serverURL = LLMConfiguration.defaultServerURL
    @AppStorage(SentenceTranslationEngine.storageKey) private var engineRaw = SentenceTranslationEngine.default.rawValue

    struct Row: Identifiable {
        let feature: LocalizedStringKey
        let destination: String
        let onDevice: Bool
        var id: String { "\(feature)" }
    }

    var body: some View {
        let _ = (appleEnabled, providerTypeRaw, engineRaw)
        Section {
            ForEach(rows) { row in
                LabeledContent {
                    Label(row.destination, systemImage: row.onDevice ? "lock.laptopcomputer" : "network")
                        .foregroundStyle(row.onDevice ? DS.Color.success : DS.Color.textSecondary)
                } label: {
                    Text(row.feature)
                }
            }
        } header: {
            Text("Where Your Text Goes")
        } footer: {
            Text("Only the selected word or sentence and its surrounding sentence are sent — never the whole book.")
                .foregroundStyle(DS.Color.textTertiary)
        }
    }

    private var rows: [Row] {
        [
            row("Hover dictionary", module: .definitionEN),
            row("Definitions, meanings, examples", module: .definitionEN),
            row("Pronunciation, etymology, mnemonics", module: .etymologyEN),
            row("Ask AI and word levels", module: nil),
            translationRow,
        ]
    }

    private func row(_ feature: LocalizedStringKey, module: ModuleType?) -> Row {
        switch AppleOnDevice.currentRoute(for: module) {
        case .appleOnDevice:
            return Row(feature: feature, destination: String(localized: "This Mac"), onDevice: true)
        case .configured:
            return Row(feature: feature, destination: providerDestination, onDevice: providerIsLocal)
        }
    }

    private var translationRow: Row {
        if SentenceTranslationEngine(rawValue: engineRaw) == .apple {
            return Row(feature: "Sentence translation",
                       destination: String(localized: "This Mac (Apple Translation)"), onDevice: true)
        }
        return row("Sentence translation", module: nil)
    }

    private var providerHost: String? {
        URL(string: serverURL)?.host?.lowercased()
    }

    /// LM Studio / Ollama on localhost never leave the machine.
    private var providerIsLocal: Bool {
        guard let host = providerHost else { return false }
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }

    private var providerDestination: String {
        if providerIsLocal { return String(localized: "This Mac (local server)") }
        return providerHost ?? serverURL
    }
}
