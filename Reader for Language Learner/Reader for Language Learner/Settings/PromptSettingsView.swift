//
//  PromptSettingsView.swift
//  Reader for Language Learner
//
//  Prompt customization: system prompt preamble override + per-module creativity tuning.
//

import SwiftUI

struct PromptSettingsView: View {

    // MARK: - System Prompt Override

    @AppStorage("customSystemPreamble") private var customPreamble = ""
    @State private var showResetConfirm = false

    // MARK: - Temperature Overrides (stored as JSON dict)

    @AppStorage("temperatureOverrides") private var temperatureOverridesJSON = "{}"

    private var temperatureOverrides: [String: Double] {
        guard let data = temperatureOverridesJSON.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: Double].self, from: data)
        else { return [:] }
        return dict
    }

    private func saveOverrides(_ dict: [String: Double]) {
        guard let data = try? JSONEncoder().encode(dict),
              let str = String(data: data, encoding: .utf8)
        else { return }
        temperatureOverridesJSON = str
    }

    // MARK: - Body

    var body: some View {
        Form {
            Section {
                preambleEditor
            } header: {
                Text("System Prompt Preamble")
            } footer: {
                Text("This text is prepended to the built-in system prompt for every module. Leave empty to use the default. Use this to add domain-specific instructions (e.g. \"Always provide IPA pronunciation\").")
                    .foregroundStyle(DS.Color.textTertiary)
            }

            Section {
                ForEach(ModuleType.allCases) { module in
                    temperatureRow(for: module)
                }
            } header: {
                Text("Creativity (Temperature)")
            } footer: {
                Text("Higher values produce more creative/varied output. Lower values are more focused and deterministic. Changes take effect on the next request.")
                    .foregroundStyle(DS.Color.textTertiary)
            }

            Section {
                HStack {
                    Spacer()
                    Button("Reset All to Defaults", role: .destructive) {
                        showResetConfirm = true
                    }
                    .controlSize(.small)
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 520)
        .confirmationDialog(
            "Reset all prompt settings to defaults?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset All", role: .destructive) {
                customPreamble = ""
                temperatureOverridesJSON = "{}"
            }
        }
    }

    // MARK: - Preamble Editor

    private var preambleEditor: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            TextEditor(text: $customPreamble)
                .font(.system(.callout, design: .monospaced))
                .frame(minHeight: 80, maxHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(DS.Spacing.sm)
                .background(DS.Color.surfaceInset)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                        .strokeBorder(DS.Color.separator.opacity(0.35), lineWidth: 0.8)
                )

            HStack {
                Text("\(customPreamble.count) characters")
                    .font(DS.Typography.caption2)
                    .foregroundStyle(DS.Color.textTertiary)

                Spacer()

                if !customPreamble.isEmpty {
                    Button("Clear") { customPreamble = "" }
                        .font(DS.Typography.caption2)
                        .controlSize(.mini)
                }
            }
        }
    }

    // MARK: - Temperature Row

    private func temperatureRow(for module: ModuleType) -> some View {
        let defaultTemp = module.recommendedTemperature
        let currentTemp = temperatureOverrides[module.rawValue] ?? defaultTemp

        return LabeledContent {
            HStack(spacing: DS.Spacing.sm) {
                Slider(
                    value: Binding(
                        get: { currentTemp },
                        set: { newVal in
                            var dict = temperatureOverrides
                            dict[module.rawValue] = newVal
                            saveOverrides(dict)
                        }
                    ),
                    in: 0...1,
                    step: 0.05
                )
                .frame(width: 140)

                Text(String(format: "%.2f", currentTemp))
                    .font(DS.Typography.mono)
                    .foregroundStyle(DS.Color.textTertiary)
                    .frame(width: 36, alignment: .trailing)

                // Reset to default
                if abs(currentTemp - defaultTemp) > 0.001 {
                    Button {
                        var dict = temperatureOverrides
                        dict.removeValue(forKey: module.rawValue)
                        saveOverrides(dict)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption)
                            .foregroundStyle(DS.Color.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Reset to default (\(String(format: "%.2f", defaultTemp)))")
                } else {
                    Color.clear.frame(width: 16)
                }
            }
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: module.iconName)
                    .font(.caption)
                    .foregroundStyle(module.accentColor)
                    .frame(width: 16)
                Text(module.shortTitle)
                    .font(DS.Typography.callout)
            }
        }
    }
}

#Preview {
    PromptSettingsView()
}
