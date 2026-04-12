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
    @State private var discoveredModels: [String] = []
    @State private var isLoadingModels = false
    @State private var showModelPicker = false

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
            HStack(spacing: DS.Spacing.xs) {
                TextField(providerType.defaultModel, text: $model)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 196)

                // Only local/openai-compatible servers expose /v1/models
                if providerType != .anthropic {
                    Button {
                        Task { await fetchModels() }
                    } label: {
                        if isLoadingModels {
                            ProgressView().controlSize(.mini).frame(width: 56)
                        } else {
                            Text("Browse…").frame(width: 56)
                        }
                    }
                    .disabled(isLoadingModels)
                    .popover(isPresented: $showModelPicker, arrowEdge: .bottom) {
                        modelPickerPopover
                    }
                }
            }
        }
    }

    private var modelPickerPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Available Models")
                .font(DS.Typography.caption.weight(.semibold))
                .foregroundStyle(DS.Color.textSecondary)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm)
            Divider()
            if discoveredModels.isEmpty {
                Text("No models found.\nIs the server running?")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(DS.Spacing.lg)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(discoveredModels, id: \.self) { m in
                            Button {
                                model = m
                                showModelPicker = false
                            } label: {
                                HStack {
                                    Text(m)
                                        .font(DS.Typography.callout)
                                        .foregroundStyle(DS.Color.textPrimary)
                                        .lineLimit(1)
                                    Spacer()
                                    if model == m {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(DS.Color.accent)
                                    }
                                }
                                .padding(.horizontal, DS.Spacing.md)
                                .padding(.vertical, DS.Spacing.sm)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, DS.Spacing.md)
                        }
                    }
                }
                .frame(maxHeight: 240)
            }
        }
        .frame(width: 320)
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

    // MARK: - Model discovery

    private func fetchModels() async {
        isLoadingModels = true
        defer { isLoadingModels = false }

        guard let url = URL(string: "\(serverURL)/v1/models") else { return }
        var req = URLRequest(url: url, timeoutInterval: 8)
        if providerType.requiresAPIKey && !apiKey.isEmpty {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        struct ModelsResponse: Decodable {
            struct ModelEntry: Decodable { let id: String }
            let data: [ModelEntry]
        }

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let response = try? JSONDecoder().decode(ModelsResponse.self, from: data)
        else { return }

        discoveredModels = response.data.map(\.id).sorted()
        showModelPicker = true
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
