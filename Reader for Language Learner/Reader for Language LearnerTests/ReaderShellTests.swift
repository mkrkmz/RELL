//
//  ReaderShellTests.swift
//  Reader for Language LearnerTests
//
//  v14 Sprint 1 — the reader shell: one selection menu for both readers and
//  the bar, a selection bar that stays small, and ⌘K reaching the View
//  menu's page commands.
//

import AppKit
import SwiftUI
import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class ReaderShellTests: XCTestCase {

    // MARK: - Right-click menu

    func testPDFAndEPUBMenusListTheSameActionsInTheSameOrder() async {
        let pdf = SelectionMenu.entries(includesNote: true, includesCopy: true)
        let epub = SelectionMenu.entries(includesNote: false, includesCopy: false)
        XCTAssertEqual(pdf.filter { $0 != .addNote && $0 != .copy && $0 != .separator },
                       epub.filter { $0 != .separator })
        XCTAssertEqual(epub, [.save, .analyze, .analyzeWith, .separator, .simplify, .retell, .separator, .highlight, .speak])
    }

    func testPassageToolsAreDisabledWithAReasonForAWord() async {
        let items = SelectionMenu.items(for: "landlady", actions: actions())
        for title in [String(localized: "Simplify"), String(localized: "Retell")] {
            let item = try? XCTUnwrap(items.first { $0.title == title })
            XCTAssertEqual(item?.isEnabled, false, title)
            XCTAssertEqual(item?.subtitle, SelectionMenu.passageOnlyReason, title)
            // WebKit's menu enables items itself; validation must still say no.
            let validation = item?.target as? NSMenuItemValidation
            XCTAssertEqual(item.flatMap { validation?.validateMenuItem($0) }, false, title)
        }
    }

    func testPassageToolsAreEnabledForAPassage() async {
        let passage = "He was hopelessly in debt to his landlady and was afraid of meeting her."
        let items = SelectionMenu.items(for: passage, actions: actions())
        let simplify = items.first { $0.title == String(localized: "Simplify") }
        XCTAssertEqual(simplify?.isEnabled, true)
        XCTAssertNil(simplify?.subtitle)
    }

    func testMenuItemsRunTheirActions() async {
        var log: [String] = []
        let items = SelectionMenu.items(for: "landlady", actions: actions { log.append($0) })
        func fire(_ item: NSMenuItem) { _ = (item.target as? NSObject)?.perform(item.action, with: item) }

        fire(items[0])
        let highlight = items.first { $0.title == String(localized: "Highlight") }
        XCTAssertEqual(highlight?.submenu?.items.count, HighlightColor.allCases.count)
        if let pink = highlight?.submenu?.items.first(where: { $0.title == HighlightColor.pink.label }) { fire(pink) }
        let analyzeWith = items.first { $0.title == String(localized: "Analyze With") }
        if let first = analyzeWith?.submenu?.items.first { fire(first) }
        fire(items.first { $0.title == String(localized: "Add Note") }!)

        XCTAssertEqual(log, ["save", "highlight-pink", "module-\(ModuleType.menuOrder[0].rawValue)", "note"])
    }

    // MARK: - Selection bar

    /// The bar floats over the page at its fitting size; it has to stay a
    /// compact capsule with the labels in it.
    func testSelectionBarStaysCompact() async {
        for isPassage in [false, true] {
            let bar = SelectionActionBar(
                onSave: {}, onAnalyze: {}, onHighlight: { _ in }, onSpeak: {}, onCopy: {},
                onSimplify: {}, onRetell: {}, isPassage: isPassage
            )
            let size = NSHostingView(rootView: bar).fittingSize
            XCTAssertLessThanOrEqual(size.width, 340, "bar is \(size)")
            XCTAssertLessThanOrEqual(size.height, 36, "bar is \(size)")
        }
    }

    // MARK: - ⌘K

    func testPaletteReachesTheViewMenusPageCommands() async {
        var log: [String] = []
        let items = ContentView.viewPaletteItems(commands(isEPUB: false) { log.append($0) })
        let ids = Set(items.map(\.id))
        for id in ["cmd-zoom-in", "cmd-zoom-out", "cmd-actual-size", "cmd-fit-width"] {
            XCTAssertTrue(ids.contains(id), id)
        }
        for theme in PageTheme.allCases { XCTAssertTrue(ids.contains("cmd-theme-\(theme.rawValue)")) }
        for mode in PDFLayoutMode.allCases { XCTAssertTrue(ids.contains("cmd-layout-\(mode.rawValue)")) }

        items.first { $0.id == "cmd-theme-sepia" }?.perform()
        items.first { $0.id == "cmd-zoom-in" }?.perform()
        XCTAssertEqual(log, ["theme-sepia", "zoom-in"])
    }

    func testPDFOnlyPageCommandsAreDisabledForABook() async {
        let items = ContentView.viewPaletteItems(commands(isEPUB: true))
        XCTAssertEqual(items.first { $0.id == "cmd-fit-width" }?.isEnabled, false)
        XCTAssertTrue(items.filter { $0.id.hasPrefix("cmd-layout-") }.allSatisfy { !$0.isEnabled })
        XCTAssertTrue(items.filter { $0.id.hasPrefix("cmd-theme-") }.allSatisfy(\.isEnabled))
    }

    // MARK: - Helpers

    private func actions(_ log: @escaping (String) -> Void = { _ in }) -> SelectionMenu.Actions {
        SelectionMenu.Actions(
            save: { log("save") },
            analyze: { log("analyze") },
            analyzeWith: { log("module-\($0.rawValue)") },
            highlight: { log("highlight-\($0.rawValue)") },
            speak: { log("speak") },
            addNote: { log("note") },
            copy: { log("copy") }
        )
    }

    private func commands(isEPUB: Bool, _ log: @escaping (String) -> Void = { _ in }) -> ReaderCommands {
        ReaderCommands(
            hasDocument: true, hasSelection: false, isSidebarVisible: true, isInspectorVisible: true,
            focusMode: false, zenMode: false, canGoToPreviousPage: false, canGoToNextPage: false,
            recentDocuments: [], isEPUBDocument: isEPUB, isCurrentPageBookmarked: false,
            isCurrentTermSaved: false, pageTheme: .original, pdfDisplayMode: .single, speechState: .idle,
            openDocument: { _ in }, closeDocument: {}, toggleSidebar: {}, toggleInspector: {},
            toggleFocusMode: {}, toggleZenMode: {}, goToPreviousPage: {}, goToNextPage: {},
            runModule: { _ in }, runLastModule: {}, clearRecentDocuments: {},
            showFind: {}, findNext: {}, findPrevious: {}, toggleBookmark: {}, toggleSaveWord: {},
            zoomIn: { log("zoom-in") }, zoomOut: { log("zoom-out") }, actualSize: {}, fitToWidth: {},
            setPageTheme: { log("theme-\($0.rawValue)") }, setPDFDisplayMode: { log("layout-\($0.rawValue)") },
            readAloud: {}, pauseSpeech: {}, resumeSpeech: {}, stopSpeech: {}
        )
    }
}
