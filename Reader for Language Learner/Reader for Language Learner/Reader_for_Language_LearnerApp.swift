//
//  Reader_for_Language_LearnerApp.swift
//  Reader for Language Learner
//
//  Created by Muhammet Korkmaz on 10.02.2026.
//

import AppIntents
import SwiftUI

/// Registers the Services provider once AppKit is fully up — the Services
/// menu ("Look Up in RELL") has no SwiftUI-native registration point.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = ServicesProvider.shared
        NSUpdateDynamicServices()
    }
}

@main
struct Reader_for_Language_LearnerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("menuBarExtraEnabled") private var menuBarExtraEnabled = true

    // Document-independent stores live at App scope so every scene — main
    // window(s), menu bar extra, HUD panel — shares one instance of each.
    @State private var savedWordsStore:     SavedWordsStore
    @State private var quickLookup:         QuickLookupService
    @State private var bookmarkStore     = PDFBookmarkStore()
    @State private var noteStore         = PDFNoteStore()
    @State private var highlightStore    = PDFHighlightStore()
    @State private var sessionStore      = ReadingSessionStore()
    @State private var recentDocumentStore = RecentDocumentStore()
    @State private var coverStore        = DocumentCoverStore()
    @State private var ankiPrefs         = AnkiModulePreferences()

    init() {
        // The HUD panel lives outside the SwiftUI scene tree, so it gets its
        // store references directly instead of through the environment.
        let savedWords = SavedWordsStore()
        let lookup = QuickLookupService()
        _savedWordsStore = State(initialValue: savedWords)
        _quickLookup = State(initialValue: lookup)
        QuickLookupPanelController.shared.configure(
            savedWordsStore: savedWords,
            quickLookup: lookup
        )

        // App Intents (Shortcuts) resolve stores through this registry.
        AppDependencyManager.shared.add(dependency: savedWords)

        // Launch-time Spotlight sync — catches edits/deletes made since the
        // last run that the per-mutation hooks may have missed.
        let wordsSnapshot = savedWords.words
        Task { SpotlightIndexer.reindexAllWords(wordsSnapshot) }

        // ⌃⌥Space — system-wide Quick Lookup HUD.
        GlobalHotKeyManager.shared.configureForQuickLookup()
    }

    var body: some Scene {
        // Value-keyed windows: nil = dashboard, URL = that document.
        // openWindow(value:) focuses an existing window for the same URL
        // instead of duplicating it.
        WindowGroup(for: URL.self) { $documentURL in
            ContentView(documentURL: $documentURL)
                .environment(savedWordsStore)
                .environment(quickLookup)
                .environment(bookmarkStore)
                .environment(noteStore)
                .environment(highlightStore)
                .environment(sessionStore)
                .environment(recentDocumentStore)
                .environment(coverStore)
                .environment(ankiPrefs)
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            ReaderMenuCommands()
        }

        // Standalone review window — study without a document open.
        Window("Vocabulary Review", id: "review") {
            QuizView(store: savedWordsStore)
                .frame(minWidth: 460, minHeight: 560)
        }
        .defaultSize(width: 460, height: 620)

        // Quick Lookup from the menu bar, even with no window open.
        MenuBarExtra(
            "Quick Lookup",
            systemImage: "character.book.closed.fill",
            isInserted: $menuBarExtraEnabled
        ) {
            MenuBarQuickLookupView()
                .environment(savedWordsStore)
                .environment(quickLookup)
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
