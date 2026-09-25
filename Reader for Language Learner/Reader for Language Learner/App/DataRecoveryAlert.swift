//
//  DataRecoveryAlert.swift
//  Reader for Language Learner
//
//  Tells the user when a data file couldn't be read at launch and was moved
//  aside (`PersistenceRecovery`). An alert rather than a toast: a toast
//  dismisses itself, and this is the one message the user must not miss —
//  their list looks empty and they need to know why and where to go.
//

import AppKit
import SwiftUI

private struct DataRecoveryAlert: ViewModifier {
    @State private var files: [PersistenceRecovery.QuarantinedFile] = []
    @Environment(\.openSettings) private var openSettings
    @AppStorage(StorageKey.settingsSelectedTab) private var settingsSelectedTab = SettingsTab.general.rawValue

    private var isPresented: Binding<Bool> {
        Binding(get: { !files.isEmpty }, set: { if !$0 { files = [] } })
    }

    private var storeNames: String {
        let names = files.map(\.localizedStoreName)
        let unique = names.enumerated().filter { names.firstIndex(of: $0.element) == $0.offset }.map(\.element)
        return unique.formatted(.list(type: .and))
    }

    func body(content: Content) -> some View {
        content
            .task {
                // Only the first window to appear takes the list.
                files = PersistenceRecovery.takePending()
            }
            .alert("Some of your data couldn't be read", isPresented: isPresented) {
                Button("Restore from Backup…") {
                    settingsSelectedTab = SettingsTab.general.rawValue
                    openSettings()
                    files = []
                }
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting(files.map(\.url))
                    files = []
                }
                Button("OK", role: .cancel) { files = [] }
            } message: {
                Text("RELL couldn't read \(storeNames), so it started without them. Nothing was deleted: the original file was set aside unchanged in RELL's data folder. You can restore a daily backup from Settings ▸ General.")
            }
    }
}

extension View {
    /// Shows the launch-time "data couldn't be read" alert, once per launch.
    func dataRecoveryAlert() -> some View {
        modifier(DataRecoveryAlert())
    }
}
