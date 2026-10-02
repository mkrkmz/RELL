//
//  DataSettingsView.swift
//  Reader for Language Learner
//
//  Settings ▸ Data (v14 S4): backups and restoring them, and the welcome
//  tour. Split from the old General tab.
//

import SwiftUI

struct DataSettingsView: View {
    @AppStorage(StorageKey.hasCompletedOnboarding) private var hasCompletedOnboarding = true

    var body: some View {
        Form {
            BackupSettingsSection()

            Section {
                Button("Show Welcome Tour Again") {
                    hasCompletedOnboarding = false
                }
                .help("Reopens the first-run setup: language pair, AI connection, and the reading tour")
            } header: {
                Text("Welcome")
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    DataSettingsView()
}
