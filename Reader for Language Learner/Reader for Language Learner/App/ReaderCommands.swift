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

    var openDocument: (URL) -> Void
    var closeDocument: () -> Void
    var toggleSidebar: () -> Void
    var toggleInspector: () -> Void
    var toggleFocusMode: () -> Void
    var goToPreviousPage: () -> Void
    var goToNextPage: () -> Void
    var runModule: (ModuleType) -> Void
    var runLastModule: () -> Void
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
    }
}

extension FocusedValues {
    @Entry var readerCommands: ReaderCommands?
}
