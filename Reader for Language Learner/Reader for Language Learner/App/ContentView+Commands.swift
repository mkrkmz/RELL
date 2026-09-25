//
//  ContentView+Commands.swift
//  Reader for Language Learner
//
//  Window state and actions published to the main menu (ReaderMenuCommands)
//  through FocusedValues.
//

import AppKit
import CoreSpotlight
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

extension ContentView {
    // MARK: - Menu Bar Bridge

    /// Snapshot of window state + actions published to the main menu
    /// (`ReaderMenuCommands`) through FocusedValues.
    var readerCommands: ReaderCommands {
        ReaderCommands(
            hasDocument: selectionState.documentURL != nil,
            hasSelection: !selectionState.selectedText
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            isSidebarVisible: showSidebar,
            isInspectorVisible: showInspector,
            focusMode: focusMode,
            zenMode: zenMode,
            canGoToPreviousPage: isEPUBDocument
                ? epubManager.canGoToPreviousChapter
                : pdfViewManager.canGoToPreviousPage,
            canGoToNextPage: isEPUBDocument
                ? epubManager.canGoToNextChapter
                : pdfViewManager.canGoToNextPage,
            recentDocuments: recentDocumentStore.recentDocuments,
            isEPUBDocument: isEPUBDocument,
            isCurrentPageBookmarked: isCurrentPageBookmarked,
            isCurrentTermSaved: isCurrentTermSaved,
            pageTheme: pageTheme,
            pdfDisplayMode: pdfDisplayMode,
            speechState: speechManager.state,
            openDocument: { openDocument($0) },
            closeDocument: { closeDocument() },
            toggleSidebar: { toggleSidebar() },
            toggleInspector: { toggleInspector() },
            toggleFocusMode: { toggleFocusMode() },
            toggleZenMode: { toggleZenMode() },
            goToPreviousPage: {
                if isEPUBDocument { epubManager.previousChapter() }
                else { pdfViewManager.goToPreviousPage() }
            },
            goToNextPage: {
                if isEPUBDocument { epubManager.nextChapter() }
                else { pdfViewManager.goToNextPage() }
            },
            runModule: { runModule($0) },
            runLastModule: { focusInspectorAndRun() },
            clearRecentDocuments: { recentDocumentStore.clear() },
            showFind: { openFindBar() },
            findNext: { findNext() },
            findPrevious: { findPrevious() },
            toggleBookmark: { toggleCurrentPageBookmark() },
            toggleSaveWord: {
                revealInspectorThenRepost(.inspectorToggleSaveWord, object: nil, forcePost: true)
            },
            zoomIn: { menuZoomIn() },
            zoomOut: { menuZoomOut() },
            actualSize: { menuActualSize() },
            fitToWidth: { pdfViewManager.fitToWidth() },
            setPageTheme: { pageThemeRaw = $0.rawValue },
            setPDFDisplayMode: { pdfDisplayModeRaw = $0.rawValue },
            readAloud: { readCurrentPageAloud() },
            pauseSpeech: { speechManager.pause() },
            resumeSpeech: { speechManager.resume() },
            stopSpeech: { speechManager.stop() }
        )
    }

    /// PDF: the current page's full text. EPUB: the current chapter's
    /// (async JS-evaluated) plain text. Either way, no character cap —
    /// whole-page reads are meant to run to completion, not truncate at the
    /// 500-char default used for word/selection speak.
    func readCurrentPageAloud() {
        if isEPUBDocument {
            Task {
                let text = await epubManager.currentChapterPlainText()
                speechManager.speakResolved(text, limit: nil)
            }
        } else {
            guard let text = pdfViewManager.pdfView?.currentPage?.string else { return }
            speechManager.speakResolved(text, limit: nil)
        }
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first,
              let type = [UTType.pdf, UTType.epub].first(where: {
                  provider.hasItemConformingToTypeIdentifier($0.identifier)
              })
        else { return false }
        provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, _ in
            let url: URL?
            if let u = item as? URL { url = u }
            else if let d = item as? Data { url = URL(dataRepresentation: d, relativeTo: nil) }
            else { url = nil }
            if let url {
                DispatchQueue.main.async {
                    openDocument(url)
                }
            }
        }
        return true
    }
}
