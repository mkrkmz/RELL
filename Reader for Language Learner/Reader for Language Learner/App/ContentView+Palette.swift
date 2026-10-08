//
//  ContentView+Palette.swift
//  Reader for Language Learner
//
//  What ⌘K can reach from this window (Roadmap v13 Sprint 5).
//

import SwiftUI

extension ContentView {

    func withCommandPalette(_ content: some View) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .commandPaletteCommand)) { _ in
                guard model.hostWindow?.isKeyWindow == true else { return }
                model.showCommandPalette = true
            }
            .sheet(isPresented: Bindable(model).showCommandPalette) {
                CommandPaletteView(items: paletteItems, pageItem: pageJumpItem)
            }
    }

    /// The View menu's page commands — zoom, layout, theme — so ⌘K reaches
    /// everything the menu does (v14 S1; before, only the menu had them).
    static func viewPaletteItems(_ commands: ReaderCommands) -> [PaletteItem] {
        let hasDocument = commands.hasDocument
        var items: [PaletteItem] = [
            PaletteItem(id: "cmd-zoom-in", kind: .command, title: String(localized: "Zoom In"),
                        icon: "plus.magnifyingglass", isEnabled: hasDocument, perform: commands.zoomIn),
            PaletteItem(id: "cmd-zoom-out", kind: .command, title: String(localized: "Zoom Out"),
                        icon: "minus.magnifyingglass", isEnabled: hasDocument, perform: commands.zoomOut),
            PaletteItem(id: "cmd-actual-size", kind: .command, title: String(localized: "Actual Size"),
                        icon: "1.magnifyingglass", isEnabled: hasDocument, perform: commands.actualSize),
            PaletteItem(id: "cmd-fit-width", kind: .command, title: String(localized: "Fit to Width"),
                        icon: "arrow.left.and.right", isEnabled: hasDocument && !commands.isEPUBDocument,
                        perform: commands.fitToWidth),
        ]
        for mode in PDFLayoutMode.allCases {
            items.append(PaletteItem(
                id: "cmd-layout-\(mode.rawValue)", kind: .command,
                title: String(localized: "Page Layout: \(mode.localizedTitle)"), icon: mode.iconName,
                isEnabled: hasDocument && !commands.isEPUBDocument,
                perform: { commands.setPDFDisplayMode(mode) }
            ))
        }
        for theme in PageTheme.allCases {
            items.append(PaletteItem(
                id: "cmd-theme-\(theme.rawValue)", kind: .command,
                title: String(localized: "Page Theme: \(theme.localizedTitle)"),
                subtitle: commands.pageTheme == theme ? String(localized: "Current") : "",
                icon: theme.iconName,
                isEnabled: hasDocument,
                perform: { commands.setPageTheme(theme) }
            ))
        }
        return items
    }

    var paletteItems: [PaletteItem] {
        let commands = readerCommands
        let hasDocument = commands.hasDocument
        let hasSelection = commands.hasSelection
        var items: [PaletteItem] = []

        func command(_ id: String, _ title: String, _ icon: String, enabled: Bool = true, _ action: @escaping () -> Void) {
            items.append(PaletteItem(id: "cmd-\(id)", kind: .command, title: title, icon: icon, isEnabled: enabled, perform: action))
        }
        command("review", String(localized: "Study Room"), "rectangle.stack") { openWindow(id: StudyRoom.windowID) }
        command("import", String(localized: "Import Web Article…"), "globe") {
            NotificationCenter.default.post(name: .importWebArticleCommand, object: nil)
        }
        command("story", String(localized: "Story From Your Words…"), "text.book.closed") {
            NotificationCenter.default.post(name: .wordStoryCommand, object: nil)
        }
        command("open", String(localized: "Open…"), "folder") { openPDF() }
        command("sidebar", commands.isSidebarVisible ? String(localized: "Hide Sidebar") : String(localized: "Show Sidebar"),
                "sidebar.left", enabled: hasDocument, commands.toggleSidebar)
        command("inspector", commands.isInspectorVisible ? String(localized: "Hide Inspector") : String(localized: "Show Inspector"),
                "sidebar.right", enabled: hasDocument, commands.toggleInspector)
        command("focus", commands.focusMode ? String(localized: "Exit Focus Mode") : String(localized: "Enter Focus Mode"),
                "rectangle.center.inset.filled", enabled: hasDocument, commands.toggleFocusMode)
        command("zen", commands.zenMode ? String(localized: "Exit Zen Mode") : String(localized: "Enter Zen Mode"),
                "moon", enabled: hasDocument, commands.toggleZenMode)
        command("glosses", String(localized: "Show Meanings Above Words"), "character.textbox",
                enabled: commands.isEPUBDocument) { glossEnabled.toggle() }
        // The selection bar's passage tools, reachable from ⌘K too (asked
        // for in the live pass — the bar shows them only on a 6+ word
        // selection, which made them hard to find).
        let passage = selectionState.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let isPassage = GradedRewrite.isEligible(passage)
        command("simplify", String(localized: "Simplify Selection to Your Level"), "text.badge.checkmark",
                enabled: isPassage) { model.gradedRewriteSource = passage }
        command("retell", String(localized: "Retell Selection in Your Own Words"), "square.and.pencil",
                enabled: isPassage) { model.retellSource = passage }
        items += Self.viewPaletteItems(commands)
        command("find", String(localized: "Find"), "magnifyingglass", enabled: hasDocument, commands.showFind)
        command("bookmark", commands.isCurrentPageBookmarked ? String(localized: "Remove Bookmark") : String(localized: "Add Bookmark"),
                "bookmark", enabled: hasDocument, commands.toggleBookmark)
        command("read-aloud", String(localized: "Read Page Aloud"), "speaker.wave.2", enabled: hasDocument, commands.readAloud)
        command("close", String(localized: "Close Document"), "xmark.square", enabled: hasDocument, commands.closeDocument)

        for module in ModuleType.allCases {
            items.append(PaletteItem(
                id: "module-\(module.rawValue)", kind: .command, title: module.title,
                subtitle: String(localized: "Run on the selection"), icon: "sparkles",
                isEnabled: hasSelection, perform: { commands.runModule(module) }
            ))
        }

        if isEPUBDocument, let document = epubManager.document {
            for entry in document.tocEntries where entry.chapterPath != nil {
                items.append(PaletteItem(
                    id: "toc-\(entry.id)", kind: .chapter, title: entry.title, icon: "list.bullet",
                    perform: { epubManager.open(tocEntry: entry) }
                ))
            }
        }

        if hasDocument {
            let target = Language.storedTarget.rawValue
            for word in savedWordsStore.words where word.language == nil || word.language == target {
                items.append(PaletteItem(
                    id: "word-\(word.id)", kind: .word, title: word.term,
                    subtitle: word.masteryLevel.localizedTitle, icon: "character.book.closed",
                    perform: {
                        if !commands.isSidebarVisible { commands.toggleSidebar() }
                        NotificationCenter.default.post(name: .revealSavedWordCommand, object: word.id)
                    }
                ))
            }
        }

        for document in recentDocumentStore.documents {
            items.append(PaletteItem(
                id: "doc-\(document.path)", kind: .document, title: document.displayTitle,
                subtitle: document.pageLabel, icon: document.isEPUB ? "book" : "doc.text",
                isEnabled: FileManager.default.fileExists(atPath: document.path),
                perform: { openDocument(document.url) }
            ))
        }
        return items
    }

    /// "Go to page 42" for a PDF (or chapter 42 of a book) when in range.
    func pageJumpItem(_ number: Int) -> PaletteItem? {
        if isEPUBDocument {
            guard number <= epubManager.chapterCount else { return nil }
            return PaletteItem(id: "goto-\(number)", kind: .page, title: String(localized: "Go to Chapter \(number)"),
                               icon: "arrow.right.circle", perform: { epubManager.openChapter(at: number - 1) })
        }
        guard selectionState.documentURL != nil, number <= pdfViewManager.pageCount else { return nil }
        return PaletteItem(id: "goto-\(number)", kind: .page, title: String(localized: "Go to Page \(number)"),
                           icon: "arrow.right.circle", perform: { pdfViewManager.goToPage(index: number - 1) })
    }
}
