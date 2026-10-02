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
        // Process-wide light/dark override (nil = follow system) — covers
        // every window incl. Settings, Review, MenuBarExtra, and the HUD
        // panel, unlike the per-window .preferredColorScheme it replaced.
        AppTheme.applyCurrent()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Debounced stores may hold an unwritten mutation — force it to disk
        // before the process exits so nothing from the last half-second is lost.
        MainActor.assumeIsolated {
            PersistenceCoordinator.flushAll()
        }
    }
}

@main
struct Reader_for_Language_LearnerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(StorageKey.menuBarExtraEnabled) private var menuBarExtraEnabled = true
    @AppStorage(StorageKey.appTheme) private var appThemeRaw = AppTheme.system.rawValue

    // Document-independent stores live at App scope so every scene — main
    // window(s), menu bar extra, HUD panel — shares one instance of each.
    @State private var savedWordsStore:     SavedWordsStore
    @State private var quickLookup:         QuickLookupService
    @State private var bookmarkStore     = PDFBookmarkStore()
    @State private var noteStore         = PDFNoteStore()
    @State private var highlightStore    = PDFHighlightStore()
    @State private var epubHighlightStore = EPUBHighlightStore()
    @State private var epubBookmarkStore = EPUBBookmarkStore()
    @State private var epubNoteStore     = EPUBNoteStore()
    @State private var sessionStore      = ReadingSessionStore()
    @State private var encounterStore    = WordEncounterStore()
    @State private var recentDocumentStore = RecentDocumentStore()
    @State private var coverStore        = DocumentCoverStore()
    @State private var ankiPrefs         = AnkiModulePreferences()
    @State private var cefrEstimator:    CEFREstimator

    init() {
        // The HUD panel lives outside the SwiftUI scene tree, so it gets its
        // store references directly instead of through the environment.
        let savedWords = SavedWordsStore()
        let lookup = QuickLookupService()
        _savedWordsStore = State(initialValue: savedWords)
        _quickLookup = State(initialValue: lookup)
        // Listens for .savedWordAdded — estimates CEFR for unrated new words.
        _cefrEstimator = State(initialValue: CEFREstimator(savedWordsStore: savedWords))
        QuickLookupPanelController.shared.configure(
            savedWordsStore: savedWords,
            quickLookup: lookup
        )

        // App Intents (Shortcuts) resolve stores through this registry.
        AppDependencyManager.shared.add(dependency: savedWords)

        // A unit-test host touches nothing outside its own process: no
        // Spotlight index, no system-wide hotkey, no notifications, no
        // backups. Its stores already live in a throwaway folder.
        guard !RELLProcess.isTestHost else { return }

        // Launch-time Spotlight sync — catches edits/deletes made since the
        // last run that the per-mutation hooks may have missed.
        let wordsSnapshot = savedWords.words
        Task { SpotlightIndexer.reindexAllWords(wordsSnapshot) }

        // ⌃⌥Space — system-wide Quick Lookup HUD.
        GlobalHotKeyManager.shared.configureForQuickLookup()

        // Daily-goal reminder — becomes the UNUserNotificationCenter delegate
        // and re-schedules if the user already opted in on a previous launch.
        DailyReminderManager.shared.configure(savedWordsStore: savedWords)
        // Once-a-day copy of every data file, newest seven kept. Every store
        // above has loaded by now, so a file that failed to load has already
        // been quarantined and can't displace yesterday's good copy.
        PersistenceBackup.runDailyIfNeeded()
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
                .environment(epubHighlightStore)
                .environment(epubBookmarkStore)
                .environment(epubNoteStore)
                .environment(sessionStore)
                .environment(encounterStore)
                .environment(recentDocumentStore)
                .environment(coverStore)
                .environment(ankiPrefs)
                .environment(cefrEstimator)
                .rellAccentTint()
        }
        .defaultSize(width: 1200, height: 800)
        .onChange(of: appThemeRaw) { _, _ in
            AppTheme.applyCurrent()
        }
        .commands {
            ReaderMenuCommands()
        }

        // Standalone review window — study without a document open.
        Window("Vocabulary Review", id: "review") {
            QuizView(store: savedWordsStore)
                .environment(encounterStore)
                .frame(minWidth: 460, minHeight: 560)
                .rellAccentTint()
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
                .rellAccentTint()
        }
        .menuBarExtraStyle(.window)

        // Native macOS Settings window — ⌘,
        Settings {
            SettingsView()
                .rellAccentTint()
        }
    }
}

/// Wraps the shared panel view so the menu bar window can dismiss itself.
private struct MenuBarQuickLookupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SavedWordsStore.self) private var savedWordsStore

    var body: some View {
        VStack(spacing: 0) {
            QuickLookupPanelView(style: .menuBar, onDismiss: { dismiss() })
            // One due word, answerable without opening a window (v13 S5).
            if !savedWordsStore.words.isEmpty {
                Divider()
                NextWordCard(store: savedWordsStore)
            }
        }
    }
}

extension Notification.Name {
    static let openPDFCommand = Notification.Name("openPDFCommand")
    /// Help ▸ What's New in RELL — the key window shows the page.
    static let whatsNewCommand = Notification.Name("whatsNewCommand")
    /// Help ▸ Reading Tour — the key window shows the four-page tour.
    static let readingTourCommand = Notification.Name("readingTourCommand")
    /// An empty Bookmarks list's button — the key window toggles a bookmark
    /// at the current page or position, as ⌘B does (v14 S3).
    static let toggleBookmarkCommand = Notification.Name("toggleBookmarkCommand")
    /// Object: the selected passage. The key window rewrites it at the
    /// reader's level (v13 Sprint 3).
    static let simplifySelectionCommand = Notification.Name("simplifySelectionCommand")
    /// File ▸ Import Web Article… — the key window shows the import sheet.
    static let importWebArticleCommand = Notification.Name("importWebArticleCommand")
    /// Object: the selected passage, to retell in the reader's own words.
    static let retellSelectionCommand = Notification.Name("retellSelectionCommand")
    /// Go ▸ Story From Your Words… — the key window shows the story sheet.
    static let wordStoryCommand = Notification.Name("wordStoryCommand")
    /// View ▸ Command Palette (⌘K).
    static let commandPaletteCommand = Notification.Name("commandPaletteCommand")
    /// Posted by SavedWordsStore.add with the new word's UUID as `object`.
    static let savedWordAdded = Notification.Name("savedWordAdded")
    /// Posted by LLM settings when the Keychain-backed API key changes.
    static let llmAPIKeyChanged = Notification.Name("llmAPIKeyChanged")
}
