//
//  ReaderMenuCommands.swift
//  Reader for Language Learner
//
//  Main-menu command hierarchy: File additions (Open Recent, Close Document),
//  View panel toggles, the Go menu, and the Modules menu.
//  Actions reach the key window through @FocusedValue(\.readerCommands).
//

import SwiftUI

struct ReaderMenuCommands: Commands {
    @FocusedValue(\.readerCommands) private var reader
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // ── File ──────────────────────────────────────────────────────
        CommandGroup(after: .newItem) {
            Button("Open…") {
                NotificationCenter.default.post(name: .openPDFCommand, object: nil)
            }
            .keyboardShortcut("o", modifiers: [.command])

            openRecentMenu

            Divider()

            Button("Close Document") { reader?.closeDocument() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(reader?.hasDocument != true)
        }

        // ── Edit (Find) ───────────────────────────────────────────────
        CommandGroup(after: .textEditing) {
            Divider()

            Button("Find…") { reader?.showFind() }
                .keyboardShortcut("f", modifiers: [.command])
                .disabled(reader?.hasDocument != true)

            Button("Find Next") { reader?.findNext() }
                .keyboardShortcut("g", modifiers: [.command])
                .disabled(reader?.hasDocument != true)

            Button("Find Previous") { reader?.findPrevious() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(reader?.hasDocument != true)
        }

        // ── View ──────────────────────────────────────────────────────
        CommandGroup(after: .sidebar) {
            Button(reader?.isSidebarVisible == true ? "Hide Sidebar" : "Show Sidebar") {
                reader?.toggleSidebar()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
            .disabled(reader == nil)

            Button(reader?.isInspectorVisible == true ? "Hide Inspector" : "Show Inspector") {
                reader?.toggleInspector()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(reader == nil)

            Divider()

            Button(reader?.focusMode == true ? "Exit Focus Mode" : "Enter Focus Mode") {
                reader?.toggleFocusMode()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(reader?.hasDocument != true)

            Divider()

            Button("Zoom In") { reader?.zoomIn() }
                .keyboardShortcut("+", modifiers: [.command])
                .disabled(reader?.hasDocument != true)

            Button("Zoom Out") { reader?.zoomOut() }
                .keyboardShortcut("-", modifiers: [.command])
                .disabled(reader?.hasDocument != true)

            Button("Actual Size") { reader?.actualSize() }
                .keyboardShortcut("0", modifiers: [.command, .shift])
                .disabled(reader?.hasDocument != true)

            Button("Fit to Width") { reader?.fitToWidth() }
                .keyboardShortcut("0", modifiers: [.command])
                .disabled(reader?.hasDocument != true || reader?.isEPUBDocument == true)

            Divider()

            pageThemeMenu

            Divider()

            Button(reader?.isCurrentPageBookmarked == true ? "Remove Bookmark" : "Add Bookmark") {
                reader?.toggleBookmark()
            }
            .keyboardShortcut("b", modifiers: [.command])
            .disabled(reader?.hasDocument != true)

            Button(reader?.isCurrentTermSaved == true ? "Remove from Saved" : "Save Word") {
                reader?.toggleSaveWord()
            }
            .keyboardShortcut("d", modifiers: [.command])
            .disabled(reader?.hasSelection != true)
        }

        // ── Go ────────────────────────────────────────────────────────
        CommandMenu("Go") {
            Button("Previous Page") { reader?.goToPreviousPage() }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled(reader?.canGoToPreviousPage != true)

            Button("Next Page") { reader?.goToNextPage() }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled(reader?.canGoToNextPage != true)

            Divider()

            Button("Vocabulary Review") { openWindow(id: "review") }
                .keyboardShortcut("v", modifiers: [.command, .option])
        }

        // ── Modules ───────────────────────────────────────────────────
        CommandMenu("Modules") {
            ForEach(Array(ModuleType.menuOrder.enumerated()), id: \.element) { index, module in
                Button(module.title) { reader?.runModule(module) }
                    .keyboardShortcut(moduleShortcut(at: index))
                    .disabled(reader?.hasSelection != true)
            }

            Divider()

            Button("Run Last Module") { reader?.runLastModule() }
                .keyboardShortcut("l", modifiers: [.command])
                .disabled(reader?.hasSelection != true)
        }
    }

    /// ⌘1…⌘9 for the first nine modules; the tenth stays shortcut-free
    /// (⌘0 belongs to Fit Width, matching zoom conventions).
    private func moduleShortcut(at index: Int) -> KeyboardShortcut? {
        guard index < 9,
              let digit = Character("\(index + 1)").unicodeScalars.first
        else { return nil }
        return KeyboardShortcut(KeyEquivalent(Character(digit)), modifiers: .command)
    }

    private var openRecentMenu: some View {
        Menu("Open Recent") {
            let recents = reader?.recentDocuments ?? []
            if recents.isEmpty {
                Button("No Recent Documents") {}
                    .disabled(true)
            } else {
                ForEach(recents.prefix(12)) { document in
                    // openWindow(value:) focuses the document if it is
                    // already open, otherwise opens a new window/tab.
                    Button(document.filename) { openWindow(value: document.url) }
                }
                Divider()
                Button("Clear Menu") { reader?.clearRecentDocuments() }
            }
        }
        .disabled(reader == nil)
    }

    /// Mirrors the toolbar's Theme menu (App/Page sections) so the choice is
    /// also reachable — and its current selection visible — from the menu bar.
    private var pageThemeMenu: some View {
        Menu("Page Theme") {
            ForEach(PageTheme.allCases) { theme in
                Button {
                    reader?.setPageTheme(theme)
                } label: {
                    HStack {
                        Label(theme.displayName, systemImage: theme.iconName)
                        if reader?.pageTheme == theme { Spacer(); Image(systemName: "checkmark") }
                    }
                }
            }
        }
        .disabled(reader?.hasDocument != true)
    }
}
