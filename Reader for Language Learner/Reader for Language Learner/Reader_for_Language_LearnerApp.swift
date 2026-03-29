//
//  Reader_for_Language_LearnerApp.swift
//  Reader for Language Learner
//
//  Created by Muhammet Korkmaz on 10.02.2026.
//

import SwiftUI

@main
struct Reader_for_Language_LearnerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open PDF…") {
                    NotificationCenter.default.post(name: .openPDFCommand, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
        }

        // Native macOS Settings window — ⌘,
        Settings {
            SettingsView()
        }
    }
}

extension Notification.Name {
    static let openPDFCommand = Notification.Name("openPDFCommand")
}
