//
//  LLMStatusItem.swift
//  Reader for Language Learner
//
//  Toolbar status light for the LLM backend: green/orange/red dot plus the
//  model name, with a popover exposing connection details and quick actions.
//

import SwiftUI

struct LLMStatusItem: View {
    var health: LLMHealthMonitor
    var circuitBreaker: CircuitBreaker

    @State private var showPopover = false

    @AppStorage(LLMConfiguration.providerTypeKey) private var providerTypeRaw: String = LLMConfiguration.defaultProviderType.rawValue
    @AppStorage(LLMConfiguration.serverURLKey)    private var serverURL: String = LLMConfiguration.defaultServerURL
    @AppStorage(LLMConfiguration.modelKey)        private var model: String = LLMConfiguration.defaultModel

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text(shortModelName)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textSecondary)
                    .lineLimit(1)
            }
        }
        .help("LLM server status — \(statusLabel)")
        .accessibilityLabel("LLM server status: \(statusLabel)")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            LLMStatusPopover(
                health: health,
                circuitBreaker: circuitBreaker,
                providerName: providerTypeRaw,
                serverURL: serverURL,
                model: model
            )
        }
        .onChange(of: showPopover) { _, shown in
            if shown { health.scheduleCheck() }
        }
    }

    /// Circuit breaker verdicts trump the passive probe: it reflects the
    /// most recent *real* requests.
    private var statusColor: Color {
        if circuitBreaker.state == .open { return DS.Color.danger }
        switch health.status {
        case .healthy:     return DS.Color.success
        case .checking:    return DS.Color.warning
        case .unreachable: return DS.Color.danger
        case .unknown:     return DS.Color.textTertiary
        }
    }

    private var statusLabel: String {
        if circuitBreaker.state == .open { return String(localized: "Unreachable") }
        switch health.status {
        case .healthy:     return String(localized: "Connected")
        case .checking:    return String(localized: "Checking…")
        case .unreachable: return String(localized: "Unreachable")
        case .unknown:     return String(localized: "Unknown")
        }
    }

    private var shortModelName: String {
        model.components(separatedBy: "/").last ?? model
    }
}

// MARK: - Popover

private struct LLMStatusPopover: View {
    var health: LLMHealthMonitor
    var circuitBreaker: CircuitBreaker
    var providerName: String
    var serverURL: String
    var model: String

    @Environment(\.openSettings) private var openSettings
    @AppStorage("settingsSelectedTab") private var settingsSelectedTab = SettingsTab.general.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(statusHeadline)
                .font(DS.Typography.headline)

            if case .unreachable(let message) = health.status {
                Text(message)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            detailRow(label: "Provider", value: providerName)
            detailRow(label: "Server", value: serverURL)
            detailRow(label: "Model", value: model)
            if let latency = health.lastLatencyMs {
                detailRow(label: "Latency", value: "\(latency) ms")
            }
            if let checkedAt = health.lastCheckedAt {
                detailRow(
                    label: "Checked",
                    value: checkedAt.formatted(date: .omitted, time: .standard)
                )
            }

            Divider()

            HStack {
                Button("Check Now") {
                    circuitBreaker.reset()
                    health.scheduleCheck()
                }
                Spacer()
                Button("Open LLM Settings…") {
                    settingsSelectedTab = SettingsTab.llm.rawValue
                    openSettings()
                }
            }
            .controlSize(.small)
        }
        .padding(DS.Spacing.md)
        .frame(width: 300)
    }

    private var statusHeadline: String {
        if circuitBreaker.state == .open { return "LLM Server Unreachable" }
        switch health.status {
        case .healthy:     return "LLM Server Connected"
        case .checking:    return "Checking Connection…"
        case .unreachable: return "LLM Server Unreachable"
        case .unknown:     return "LLM Server Status Unknown"
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.textTertiary)
                .frame(width: 56, alignment: .leading)
            Text(value)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.textSecondary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
