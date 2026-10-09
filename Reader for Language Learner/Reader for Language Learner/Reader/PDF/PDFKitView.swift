//
//  PDFKitView.swift
//  Reader for Language Learner
//
//  Created by Codex on 10.02.2026.
//

import NaturalLanguage
import os
import PDFKit
import QuartzCore // For CIFilter
import SwiftUI

struct PDFKitView: NSViewRepresentable {
    let documentURL: URL?
    @Binding var selectedText: String
    @Binding var contextSentence: String?
    var searchManager: PDFSearchManager
    var pdfViewManager: PDFViewManager
    var savedWordsStore: SavedWordsStore
    var noteStore: PDFNoteStore
    var highlightStore: PDFHighlightStore
    var quickLookup: QuickLookupService
    var toastCenter: ToastCenter
    var hoverEnabled: Bool = true
    var pageTheme: PageTheme = .original
    var displayMode: PDFLayoutMode = .single

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedText: $selectedText,
                    contextSentence: $contextSentence,
                    searchManager: searchManager,
                    savedWordsStore: savedWordsStore,
                    noteStore: noteStore,
                    highlightStore: highlightStore,
                    quickLookup: quickLookup,
                    toastCenter: toastCenter,
                    hoverEnabled: hoverEnabled)
    }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = RELLPDFView()
        pdfView.autoScales = true
        // Bounds enable native trackpad pinch-to-zoom (U4) without letting the
        // page shrink to nothing or blow up past legibility. Button zoom and
        // Fit Width still work within the same range.
        pdfView.minScaleFactor = 0.25
        pdfView.maxScaleFactor = 6.0
        pdfView.displayMode = displayMode.kitDisplayMode
        pdfView.displayDirection = .vertical

        // Publish the shared PDFView so the thumbnail sidebar can connect.
        pdfViewManager.attach(pdfView)

        context.coordinator.attach(to: pdfView)
        context.coordinator.currentDisplayMode = displayMode
        context.coordinator.requestDocumentUpdate(using: documentURL)
        context.coordinator.applyTheme(pageTheme)
        return pdfView
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        context.coordinator.selectedText = $selectedText
        context.coordinator.contextSentence = $contextSentence
        context.coordinator.searchManager = searchManager
        context.coordinator.savedWordsStore = savedWordsStore
        context.coordinator.noteStore = noteStore
        context.coordinator.highlightStore = highlightStore
        context.coordinator.quickLookup = quickLookup
        context.coordinator.toastCenter = toastCenter
        context.coordinator.setHoverEnabled(hoverEnabled)
        context.coordinator.requestDocumentUpdate(using: documentURL)
        context.coordinator.applyTheme(pageTheme)
        context.coordinator.applyDisplayMode(displayMode)
        context.coordinator.refreshHighlights()
    }

    static func dismantleNSView(_ nsView: PDFView, coordinator: Coordinator) {
        coordinator.detach()
    }

    // MARK: - Layout Overlay

    /// An NSView that passes all clicks through to the view underneath.
    class PassthroughOverlayView: NSView {
        /// Off the main actor: on macOS 15 a main-actor deinit run outside a
        /// task crashes when it releases another one (v16 S0, CI crash reports).
        nonisolated deinit {}

        override func hitTest(_ point: NSPoint) -> NSView? {
            // Return nil to let the event pass through to the PDFView below
            return nil
        }
    }
}
