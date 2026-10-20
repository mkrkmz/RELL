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
    @AppStorage(LLMConfiguration.modelKey) private var model = LLMConfiguration.defaultModel
    @AppStorage(StorageKey.updateCheckEnabled) private var updateCheckEnabled = true

    struct Row: Identifiable {
        let feature: LocalizedStringKey
        let destination: String
        let onDevice: Bool
        var id: String { "\(feature)" }
    }

    var body: some View {
        let _ = (appleEnabled, providerTypeRaw, engineRaw, model, updateCheckEnabled)
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
            Text("Only the selected word or sentence and its surrounding sentence are sent — never the whole book. A recap sends the last page or two you read; a warm-up sends a list of words from the chapter; a comprehension check sends the part of the chapter you've read, or the pages you chose. If Apple's model declines, a recap or warm-up goes to your AI provider.")
                .foregroundStyle(DS.Color.textTertiary)
        }
    }

    private var rows: [Row] {
        [
            row("Hover dictionary", module: .definitionEN),
            row("Definitions, meanings, examples", module: .definitionEN),
            row("Pronunciation, etymology, mnemonics", module: .etymologyEN),
            row("Ask AI and word levels", module: nil),
            row("Recaps and chapter warm-ups", module: nil),
            row("Grammar explanations", module: .etymologyEN),
            // v19 S3: your sentence with the word; the part of the chapter you read.
            row("Sentence writing", module: nil),
            row("Comprehension checks", module: nil),
            // v19 S4: recognised on this Mac, never recorded.
            Row(feature: "Repeating aloud",
                destination: String(localized: "This Mac (on-device speech recognition)"), onDevice: true),
            translationRow,
        ] + ownModulesRow + [
            Row(feature: "Web article import",
                destination: String(localized: "Only the site you import from"), onDevice: false),
        ] + (updateCheckEnabled ? [
            // v17 S3: a request, nothing of yours in it.
            Row(feature: "Update check",
                destination: String(localized: "GitHub — reads the version number, sends nothing"), onDevice: false),
        ] : [])
    }

    private func row(_ feature: LocalizedStringKey, module: ModuleType?) -> Row {
        switch AppleOnDevice.currentRoute(for: module) {
        case .appleOnDevice:
            return Row(feature: feature, destination: String(localized: "This Mac"), onDevice: true)
        case .configured:
            return Row(feature: feature, destination: providerDestination, onDevice: providerIsLocal)
        }
    }

    /// v18 S3: your own modules go where their engine says; a module set to
    /// Apple falls back to your provider when Apple's model isn't there.
    private var ownModulesRow: [Row] {
        let modules = CustomModuleStore.shared.modules
        guard !modules.isEmpty else { return [] }
        let appleReady = AppleOnDevice.currentRoute(for: nil) == .appleOnDevice
        if appleReady, modules.allSatisfy({ $0.engine == .apple }) {
            return [Row(feature: "Your own modules", destination: String(localized: "This Mac"), onDevice: true)]
        }
        return [Row(feature: "Your own modules", destination: providerDestination, onDevice: providerIsLocal)]
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

    /// LM Studio / Ollama on localhost never leave the machine — unless
    /// the model is one of Ollama's cloud models (v17 S1).
    private var providerIsLocal: Bool {
        LLMConfiguration.runsOnThisMac(type: LLMProviderType(rawValue: providerTypeRaw) ?? .lmStudio,
                                       serverURL: serverURL, model: model)
    }

    private var providerDestination: String {
        if providerIsLocal { return String(localized: "This Mac (local server)") }
        if DiagnosticReport.localAddress(serverURL) != nil { return String(localized: "Ollama's cloud (through the local server)") }
        return providerHost ?? serverURL
    }
}
