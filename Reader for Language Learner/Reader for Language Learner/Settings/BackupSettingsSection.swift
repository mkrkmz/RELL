//
//  BackupSettingsSection.swift
//  Reader for Language Learner
//
//  Settings ▸ General ▸ Backups: restore one of the automatic daily copies,
//  or export/import the whole data set as a folder (new Mac, second copy).
//  Every restore relaunches the app — see `PersistenceBackup.restore`.
//

import AppKit
import SwiftUI

struct BackupSettingsSection: View {
    @State private var backups: [PersistenceBackup.Backup] = []
    @State private var pendingRestore: URL?
    @State private var pendingRestoreLabel = ""
    @State private var errorMessage: String?

    var body: some View {
        Section {
            HStack {
                Text("Daily Backups")
                Spacer()
                if backups.isEmpty {
                    Text("None yet")
                        .foregroundStyle(DS.Color.textTertiary)
                } else {
                    Menu("Restore…") {
                        ForEach(backups) { backup in
                            Button(backup.date.formatted(date: .complete, time: .omitted)) {
                                confirmRestore(from: backup.url, label: backup.date.formatted(date: .abbreviated, time: .omitted))
                            }
                        }
                    }
                    .fixedSize()
                }
            }

            HStack {
                Button("Export Backup…") { exportBackup() }
                Button("Import Backup…") { importBackup() }
                Spacer()
                Button("Show in Finder") { showBackupsFolder() }
                    .disabled(backups.isEmpty)
            }
        } header: {
            Text("Backups")
        } footer: {
            Text("RELL copies your words, notes, highlights, bookmarks and reading history once a day and keeps the last seven. Restoring replaces what's there now and relaunches RELL; the current data is saved as its own backup first.")
                .foregroundStyle(DS.Color.textTertiary)
        }
        .onAppear { backups = PersistenceBackup.dailyBackups() }
        .alert(
            "Restore the backup from \(pendingRestoreLabel)?",
            isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } })
        ) {
            Button("Restore and Relaunch", role: .destructive) { performRestore() }
            Button("Cancel", role: .cancel) { pendingRestore = nil }
        } message: {
            Text("Your words, notes, highlights, bookmarks and reading history will be replaced with the backup's. RELL will quit and open again.")
        }
        .alert(
            "Backup failed",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Actions

    private func confirmRestore(from folder: URL, label: String) {
        pendingRestoreLabel = label
        pendingRestore = folder
    }

    private func performRestore() {
        guard let folder = pendingRestore else { return }
        pendingRestore = nil
        do {
            try PersistenceBackup.restore(from: folder)
            PersistenceBackup.relaunch()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportBackup() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Export Here")
        panel.message = String(localized: "Choose where to save a copy of all your RELL data.")
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        do {
            // The copy on disk is only as fresh as the last debounced write.
            PersistenceCoordinator.flushAll()
            let folder = try PersistenceBackup.export(to: parent)
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importBackup() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = String(localized: "Restore")
        panel.message = String(localized: "Choose a RELL Backup folder.")
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        guard PersistenceBackup.isBackupFolder(folder) else {
            errorMessage = String(localized: "That folder doesn't contain a RELL backup.")
            return
        }
        confirmRestore(from: folder, label: folder.lastPathComponent)
    }

    private func showBackupsFolder() {
        guard let latest = backups.first else { return }
        NSWorkspace.shared.activateFileViewerSelecting([latest.url])
    }
}
