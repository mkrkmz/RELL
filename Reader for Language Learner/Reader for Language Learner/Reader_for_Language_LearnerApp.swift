//
//  Reader_for_Language_LearnerApp.swift
//  Reader for Language Learner
//
//  Created by Muhammet Korkmaz on 10.02.2026.
//

import SwiftUI

@main
struct Reader_for_Language_LearnerApp: App {
    @AppStorage("menuBarExtraEnabled") private var menuBarExtraEnabled = true

    init() {
        // ⌃⌥Space — system-wide Quick Lookup HUD.
        GlobalHotKeyManager.shared.configureForQuickLookup()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            ReaderMenuCommands()
        }

        // Quick Lookup from the menu bar, even with no window open.
        MenuBarExtra(
            "Quick Lookup",
            systemImage: "character.book.closed.fill",
            isInserted: $menuBarExtraEnabled
        ) {
            MenuBarQuickLookupView()
        }
        .menuBarExtraStyle(.window)

        // Native macOS Settings window — ⌘,
        Settings {
            SettingsView()
        }
    }
}

/// Wraps the shared panel view so the menu bar window can dismiss itself.
private struct MenuBarQuickLookupView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        QuickLookupPanelView(style: .menuBar, onDismiss: { dismiss() })
    }
}

extension Notification.Name {
    static let openPDFCommand = Notification.Name("openPDFCommand")
}
