//
//  UpdateViews.swift
//  Reader for Language Learner
//
//  A newer RELL (Roadmap v17 Sprint 3, approved mockup): the home screen's
//  banner, Help ▸ Check for Updates…, and Settings ▸ Data ▸ Updates.
//  Download opens the release page in the browser; nothing is installed.
//

import AppKit
import SwiftUI

/// Home screen: "RELL 1.47.0 is ready", until closed for that version.
struct UpdateNoticeBanner: View {
    var checker = UpdateChecker.shared
    @State private var showNotes = false

    var body: some View {
        if let release = checker.bannerRelease {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(DS.Color.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("RELL \(release.version) is ready")
                        .font(DS.Typography.callout.weight(.semibold))
                    Text("You're using \(checker.appVersion).")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                }
                Spacer(minLength: 0)
                Button("What's New") { showNotes = true }
                    .controlSize(.small)
                // Secondary: the home screen's one primary is Open (v18 S1).
                Button("Download") { NSWorkspace.shared.open(release.pageURL) }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                Button("Hide", systemImage: "xmark") { checker.hideBanner(for: release) }
                    .buttonStyle(.dsIconSecondary)
                    .help("Hide for this version")
                    .accessibilityLabel("Hide for this version")
            }
            .padding(DS.Spacing.md)
            .background(DS.Color.accentSubtle, in: RoundedRectangle(cornerRadius: DS.Radius.md))
            .sheet(isPresented: $showNotes) {
                UpdateSheet(checker: checker, checksOnAppear: false) { showNotes = false }
            }
        }
    }
}

/// Help ▸ Check for Updates…: checks, then says what it found.
struct UpdateSheet: View {
    var checker = UpdateChecker.shared
    var checksOnAppear = true
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: DS.Spacing.lg) {
            switch checker.state {
            case .idle, .checking:
                ProgressView("Checking for updates…")
                    .padding(DS.Spacing.xl)
            case .upToDate:
                header("checkmark.seal", title: "RELL is up to date",
                       subtitle: String(localized: "\(checker.appVersion) is the latest version."))
            case .failed(let message):
                header("exclamationmark.triangle", title: "Couldn't check for updates", subtitle: message)
            case .available(let release):
                header("arrow.down.circle", title: "RELL \(release.version) is ready",
                       subtitle: String(localized: "You're using \(checker.appVersion). After downloading, drag the new RELL into Applications — your words and settings stay as they are."))
                if !release.notes.isEmpty {
                    ScrollView {
                        Text(LocalizedStringKey(release.notes))
                            .font(DS.Typography.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(DS.Spacing.md)
                    }
                    .frame(maxHeight: 260)
                    .background(DS.Color.surfaceInset, in: RoundedRectangle(cornerRadius: DS.Radius.md))
                }
            }

            HStack {
                if case .available(let release) = checker.state {
                    Button("Later", action: onClose)
                    Spacer()
                    Button("Download") {
                        NSWorkspace.shared.open(release.pageURL)
                        onClose()
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Spacer()
                    Button("Done", action: onClose)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(DS.Spacing.xl)
        .frame(width: 440)
        .task {
            if checksOnAppear { await checker.check() }
        }
    }

    private func header(_ icon: String, title: LocalizedStringKey, subtitle: String) -> some View {
        VStack(spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .font(DS.Typography.icon(30, weight: .medium))
                .foregroundStyle(DS.Color.accent)
            Text(title)
                .font(DS.Typography.headline)
            Text(subtitle)
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Color.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Settings ▸ Data ▸ Updates.
struct UpdatesSettingsSection: View {
    @AppStorage(StorageKey.updateCheckEnabled) private var enabled = true
    var checker = UpdateChecker.shared

    var body: some View {
        Section {
            Toggle(isOn: $enabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Check for updates automatically")
                    Text("At most once a day, RELL asks GitHub for the latest version number. It never downloads or installs anything itself.")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                }
            }
            HStack {
                Text(status)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
                Spacer()
                if checker.state == .checking {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Check Now") { Task { await checker.check() } }
                        .controlSize(.small)
                }
            }
        } header: {
            Text("Updates")
        }
    }

    private var status: String {
        let last = checker.lastCheck.map { $0.formatted(.relative(presentation: .named)) }
        switch checker.state {
        case .available(let release): return String(localized: "RELL \(release.version) is ready.")
        case .upToDate:               return String(localized: "Up to date (\(checker.appVersion)).")
        case .failed(let message):    return message
        case .idle, .checking:
            return last.map { String(localized: "Last checked \($0).") } ?? String(localized: "Not checked yet.")
        }
    }
}
