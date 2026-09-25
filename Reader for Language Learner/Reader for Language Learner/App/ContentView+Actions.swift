//
//  ContentView+Actions.swift
//  Reader for Language Learner
//
//  Document, find, zoom, panel, bookmark and inspector actions. State
//  transitions live in ReaderWindowModel; these add animation and stores.
//

import AppKit
import CoreSpotlight
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

extension ContentView {
    // MARK: - Actions

    func openPDF() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf, .epub]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openDocument(url)
    }

    func openDocument(_ url: URL) {
        if selectionState.documentURL == nil || selectionState.documentURL == url {
            // Dashboard (or same document): this window adopts the document.
            // Setting both bindings here pre-empts the `.onChange(of:
            // documentURL)` guard below (`selectionState.documentURL` is
            // already equal to `newValue` by the time that closure runs),
            // so this is the one place that reliably sees "a document was
            // just opened in this window" for the dashboard-click path —
            // restore the reading position directly instead of relying on
            // onChange/onAppear to catch it.
            documentURL = url
            selectionState.documentURL = url
            closeFindBar()
            restorePageIfPDF(url)
        } else {
            // Another document is already on screen — open side by side
            // (a native tab by default). openWindow dedupes by URL.
            openWindow(value: url)
        }
    }

    /// Closes the current document and returns to the Home dashboard.
    /// Session end and last-page persistence are handled by the
    /// `onChange(of: selectionState.documentURL)` / page-change observers.
    func closeDocument() {
        documentURL = nil
        selectionState.documentURL = nil
        selectionState.selectedText = ""
        selectionState.contextSentence = nil
        closeFindBar()
    }

    func openFindBar() { model.openFindBar() }
    func closeFindBar() { model.closeFindBar() }
    func findNext() { model.findNext() }
    func findPrevious() { model.findPrevious() }

    /// Menu-bar mirror of the toolbar's zoom/font-size controls — EPUB has
    /// no optical zoom, so "zoom" steps its reader font size instead.
    func menuZoomIn() {
        if isEPUBDocument { epubFontSize = min(EPUBTypography.maxFontSize, epubFontSize + 1) }
        else { pdfViewManager.zoomIn() }
    }

    func menuZoomOut() {
        if isEPUBDocument { epubFontSize = max(EPUBTypography.minFontSize, epubFontSize - 1) }
        else { pdfViewManager.zoomOut() }
    }

    /// "Actual Size" — 100% for PDF, the default reader font size for EPUB.
    func menuActualSize() {
        if isEPUBDocument { epubFontSize = EPUBTypography.defaultFontSize }
        else { pdfViewManager.actualSize() }
    }

    var isCurrentTermSaved: Bool {
        let term = selectionState.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return false }
        return savedWordsStore.isSaved(
            term: term,
            pdfFilename: selectionState.documentURL?.deletingPathExtension().lastPathComponent,
            pageNumber: currentPageNumber
        )
    }

    func toggleSidebar() {
        withAnimation(DS.Animation.respecting(DS.Animation.standard, reduceMotion: reduceMotion)) {
            model.toggleSidebar()
        }
    }

    func toggleInspector() {
        withAnimation(DS.Animation.respecting(DS.Animation.standard, reduceMotion: reduceMotion)) {
            model.toggleInspector()
        }
    }

    /// Symmetric curve in both directions — entering and exiting focus mode
    /// should feel the same, not snap one way and glide the other.
    func toggleFocusMode() {
        withAnimation(DS.Animation.respecting(DS.Animation.spring, reduceMotion: reduceMotion)) {
            model.toggleFocusMode()
        }
    }

    /// Zen mode also drives the window in/out of macOS full-screen.
    func toggleZenMode() {
        var fullScreen = false
        withAnimation(DS.Animation.respecting(DS.Animation.spring, reduceMotion: reduceMotion)) {
            fullScreen = model.toggleZenMode()
        }
        model.setWindowFullScreen(fullScreen)
    }

    func exitZenChrome() {
        withAnimation(DS.Animation.respecting(DS.Animation.spring, reduceMotion: reduceMotion)) {
            model.exitZenChrome()
        }
    }

    /// Points the annotation stores at this window's undo manager so their
    /// mutations register undo/redo.
    func wireUndoManagers() {
        highlightStore.undoManager = undoManager
        noteStore.undoManager = undoManager
        bookmarkStore.undoManager = undoManager
        epubHighlightStore.undoManager = undoManager
        epubNoteStore.undoManager = undoManager
        epubBookmarkStore.undoManager = undoManager
    }

    var isCurrentPageBookmarked: Bool {
        guard let filename = selectionState.documentURL?.deletingPathExtension().lastPathComponent
        else { return false }
        if isEPUBDocument {
            return epubBookmarkStore.isBookmarked(
                filename: filename,
                chapterIndex: epubManager.chapterIndex,
                near: epubManager.scrollFraction
            )
        }
        guard let idx = currentPageNumber.map({ $0 - 1 }) else { return false }
        return bookmarkStore.isBookmarked(filename: filename, pageIndex: idx)
    }

    func toggleCurrentPageBookmark() {
        guard let filename = selectionState.documentURL?.deletingPathExtension().lastPathComponent
        else { return }
        if isEPUBDocument {
            toggleEPUBBookmark(filename: filename)
            return
        }
        guard let pageNum = currentPageNumber else { return }
        let pageIndex = pageNum - 1
        let pageLabel = "Page \(pageNum)"
        let added = bookmarkStore.toggle(filename: filename, pageIndex: pageIndex, pageLabel: pageLabel)
        toastCenter.show(
            added ? String(localized: "Bookmark added") : String(localized: "Bookmark removed"),
            variant: .info
        )
    }

    /// EPUB path: the position is captured immediately; the snippet (first
    /// visible line, the row label) arrives async from the WebView — if an
    /// existing bookmark is near this position it's removed synchronously,
    /// otherwise the add waits for the snippet (falling back to "" on failure).
    func toggleEPUBBookmark(filename: String) {
        let chapterIndex = epubManager.chapterIndex
        let fraction = epubManager.scrollFraction
        if let existing = epubBookmarkStore.bookmark(for: filename, chapterIndex: chapterIndex, near: fraction) {
            epubBookmarkStore.remove(id: existing.id)
            toastCenter.show(String(localized: "Bookmark removed"), variant: .info)
            return
        }
        Task {
            let snippet = await epubManager.visibleSnippet()
            // Re-check: a second ⌘B may have landed while the JS ran.
            guard epubBookmarkStore.bookmark(for: filename, chapterIndex: chapterIndex, near: fraction) == nil
            else { return }
            epubBookmarkStore.add(EPUBBookmark(
                epubFilename: filename,
                chapterIndex: chapterIndex,
                scrollFraction: fraction,
                snippet: snippet
            ))
            toastCenter.show(String(localized: "Bookmark added"), variant: .info)
        }
    }

    func focusInspectorAndRun() {
        revealInspectorThenRepost(.inspectorRunLastModule, object: nil, forcePost: true)
    }

    func runModule(_ module: ModuleType) {
        revealInspectorThenRepost(.inspectorRunModule, object: module.rawValue, forcePost: true)
    }

    func revealInspectorThenRepost(_ name: Notification.Name, object: Any?, forcePost: Bool = false) {
        model.revealInspectorThenPost(name, object: object, forcePost: forcePost)
    }
}
