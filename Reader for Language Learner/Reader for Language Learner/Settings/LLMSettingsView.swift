//
//  LLMSettingsView.swift
//  Reader for Language Learner
//
//  LLM provider selection, server URL, model name, API key, and connection test.
//

import SwiftUI

struct LLMSettingsView: View {

    @AppStorage(LLMConfiguration.providerTypeKey) private var providerTypeRaw = LLMConfiguration.defaultProviderType.rawValue
    @AppStorage(LLMConfiguration.serverURLKey)    private var serverURL = LLMConfiguration.defaultServerURL
    @AppStorage(LLMConfiguration.modelKey)        private var model     = LLMConfiguration.defaultModel
    @AppStorage(LLMConfiguration.timeoutKey)      private var timeout: Double = LLMConfiguration.defaultTimeout
    @AppStorage(LLMConfiguration.apiKeyKey)       private var apiKey    = ""

    @State private var connectionStatus: ConnectionStatus = .idle

    private var providerType: LLMProviderType {
        LLMProviderType(rawValue: providerTypeRaw) ?? .lmStudio
    }

    // MARK: - Body

    var body: some View {
        Form {
            Section {
                providerRow
            } header: {
                Text("Provider")
            }

            Section {
                serverURLRow
                modelRow
                if providerType.requiresAPIKey {
                    apiKeyRow
                }
                timeoutRow
            } header: {
                Text(providerType.rawValue)
            } footer: {
                Text(providerFooterText)
                    .foregroundStyle(DS.Color.textTertiary)
            }

            Section {
                connectionTestRow
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: providerType.requiresAPIKey ? 420 : 380)
        .onChange(of: serverURL)       { connectionStatus = .idle }
        .onChange(of: model)           { connectionStatus = .idle }
        .onChange(of: providerTypeRaw) { connectionStatus = .idle }
        .onChange(of: apiKey)          { connectionStatus = .idle }
    }

    // MARK: - Provider Picker

    private var providerRow: some View {
        LabeledContent("Backend") {
            Picker("", selection: $providerTypeRaw) {
                ForEach(LLMProviderType.allCases) { provider in
                    Label(provider.rawValue, systemImage: provider.iconName)
                        .tag(provider.rawValue)
                }
            }
            .labelsHidden()
            .frame(width: 260)
            .onChange(of: providerTypeRaw) { _, newValue in
                applyProviderDefaults(for: newValue)
            }
        }
    }

    // MARK: - Server URL

    private var serverURLRow: some View {
        LabeledContent("Server URL") {
            TextField(providerType.defaultServerURL, text: $serverURL)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
        }
    }

    // MARK: - Model

    private var modelRow: some View {
        LabeledContent("Model") {
            TextField(providerType.defaultModel, text: $model)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
        }
    }

    // MARK: - API Key

    private var apiKeyRow: some View {
        LabeledContent("API Key") {
            SecureField("sk-...", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
        }
    }

    // MARK: - Timeout

    private var timeoutRow: some View {
        LabeledContent("Request Timeout") {
            HStack(spacing: DS.Spacing.sm) {
                Slider(
                    value: $timeout,
                    in: LLMConfiguration.minTimeout...LLMConfiguration.maxTimeout,
                    step: 5
                )
                .frame(width: 200)
                Text("\(Int(timeout))s")
                    .font(DS.Typography.mono)
                    .foregroundStyle(DS.Color.textTertiary)
                    .frame(width: 36, alignment: .trailing)
                Button {
                    timeout = LLMConfiguration.defaultTimeout
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .foregroundStyle(DS.Color.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Reset to default (30s)")
            }
        }
    }

    // MARK: - Connection Test

    private var connectionTestRow: some View {
        HStack(spacing: DS.Spacing.md) {
            Button("Test Connection") {
                Task { await testConnection() }
            }
            .disabled(connectionStatus == .testing)

            connectionIndicator

            Spacer()

            Button("Reset to Defaults") {
                applyProviderDefaults(for: providerTypeRaw)
                apiKey  = ""
                timeout = LLMConfiguration.defaultTimeout
                connectionStatus = .idle
            }
            .controlSize(.small)
            .foregroundStyle(DS.Color.textSecondary)
        }
    }

    private var connectionIndicator: some View {
        HStack(spacing: DS.Spacing.xs) {
            if connectionStatus == .testing {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: connectionStatus.iconName)
                    .foregroundStyle(connectionStatus.color)
                    .symbolEffect(.pulse, isActive: connectionStatus == .testing)
            }
            Text(connectionStatus.label)
                .font(DS.Typography.caption)
                .foregroundStyle(connectionStatus.color)
                .lineLimit(2)
                .frame(maxWidth: 280, alignment: .leading)
        }
        .animation(DS.Animation.standard, value: connectionStatus)
    }

    // MARK: - Footer text

    private var providerFooterText: String {
        switch providerType {
        case .lmStudio:
            return "Start LM Studio, load a model, and enable the local server before using RELL."
        case .ollama:
            return "Start Ollama with 'ollama serve' and pull a model before using RELL."
        case .openAI:
            return "Enter your API key and model name. Works with OpenAI, OpenRouter, Together, and any OpenAI-compatible API."
        case .anthropic:
            return "Enter your Anthropic API key. Get one at console.anthropic.com."
        }
    }

    // MARK: - Helpers

    private func applyProviderDefaults(for rawValue: String) {
        guard let type = LLMProviderType(rawValue: rawValue) else { return }
        serverURL = type.defaultServerURL
        model     = type.defaultModel
    }

    // MARK: - Test logic

    private func testConnection() async {
        connectionStatus = .testing
        let provider = LLMConfiguration().makeProvider()
        do {
            _ = try await provider.chat(
                system: "You are a test assistant.",
                user: "Reply with one word: OK",
                temperature: 0,
                maxTokens: 8,
                topP: 1
            )
            connectionStatus = .success
        } catch {
            connectionStatus = .failure(error.localizedDescription)
        }
    }
}

// MARK: - ConnectionStatus

private enum ConnectionStatus: Equatable {
    case idle
    case testing
    case success
    case failure(String)

    var label: String {
        switch self {
        case .idle:           return "Not tested"
        case .testing:        return "Connecting…"
        case .success:        return "Connected"
        case .failure(let e): return e
        }
    }

    var iconName: String {
        switch self {
        case .idle:    return "circle"
        case .testing: return "circle.dotted"
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        }
    }

    var color: SwiftUI.Color {
        switch self {
        case .idle:    return DS.Color.textTertiary
        case .testing: return DS.Color.accent
        case .success: return DS.Color.success
        case .failure: return DS.Color.danger
        }
    }
}

#Preview {
    LLMSettingsView()
}
