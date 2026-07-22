//
//  ReaderCommands.swift
//  Reader for Language Learner
//
//  Window-scoped reader state and actions, published to the menu bar
//  through FocusedValues so main-menu commands can drive the key window.
//

import SwiftUI

struct ReaderCommands {
    var hasDocument: Bool
    var hasSelection: Bool
    var isSidebarVisible: Bool
    var isInspectorVisible: Bool
    var focusMode: Bool
    var canGoToPreviousPage: Bool
    var canGoToNextPage: Bool
    var recentDocuments: [RecentDocument]
    var isEPUBDocument: Bool
    var isCurrentPageBookmarked: Bool
    var isCurrentTermSaved: Bool
    var pageTheme: PageTheme
    var pdfDisplayMode: PDFLayoutMode
    var speechState: SpeechManager.PlaybackState

    var openDocument: (URL) -> Void
    var closeDocument: () -> Void
    var toggleSidebar: () -> Void
    var toggleInspector: () -> Void
    var toggleFocusMode: () -> Void
    var goToPreviousPage: () -> Void
    var goToNextPage: () -> Void
    var runModule: (ModuleType) -> Void
    var runLastModule: () -> Void
    var clearRecentDocuments: () -> Void

    var showFind: () -> Void
    var findNext: () -> Void
    var findPrevious: () -> Void
    var toggleBookmark: () -> Void
    var toggleSaveWord: () -> Void
    var zoomIn: () -> Void
    var zoomOut: () -> Void
    var actualSize: () -> Void
    var fitToWidth: () -> Void
    var setPageTheme: (PageTheme) -> Void
    var setPDFDisplayMode: (PDFLayoutMode) -> Void

    var readAloud: () -> Void
    var pauseSpeech: () -> Void
    var resumeSpeech: () -> Void
    var stopSpeech: () -> Void
}

// Menus only need to re-render when the observable state changes;
// closures are identity-free, so equate on the state fields alone.
extension ReaderCommands: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.hasDocument == rhs.hasDocument
            && lhs.hasSelection == rhs.hasSelection
            && lhs.isSidebarVisible == rhs.isSidebarVisible
            && lhs.isInspectorVisible == rhs.isInspectorVisible
            && lhs.focusMode == rhs.focusMode
            && lhs.canGoToPreviousPage == rhs.canGoToPreviousPage
            && lhs.canGoToNextPage == rhs.canGoToNextPage
            && lhs.recentDocuments == rhs.recentDocuments
            && lhs.isEPUBDocument == rhs.isEPUBDocument
            && lhs.isCurrentPageBookmarked == rhs.isCurrentPageBookmarked
            && lhs.isCurrentTermSaved == rhs.isCurrentTermSaved
            && lhs.pageTheme == rhs.pageTheme
            && lhs.pdfDisplayMode == rhs.pdfDisplayMode
            && lhs.speechState == rhs.speechState
    }
}

extension FocusedValues {
    @Entry var readerCommands: ReaderCommands?
}
