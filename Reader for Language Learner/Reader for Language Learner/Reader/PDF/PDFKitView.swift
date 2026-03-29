//
//  PDFKitView.swift
//  Reader for Language Learner
//
//  Created by Codex on 10.02.2026.
//

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
    var pageTheme: PageTheme = .original

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedText: $selectedText,
                    contextSentence: $contextSentence,
                    searchManager: searchManager, 
                    savedWordsStore: savedWordsStore)
    }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = RELLPDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical

        // Publish the shared PDFView so the thumbnail sidebar can connect.
        pdfViewManager.attach(pdfView)

        context.coordinator.attach(to: pdfView)
        context.coordinator.requestDocumentUpdate(using: documentURL)
        context.coordinator.applyTheme(pageTheme)
        return pdfView
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        context.coordinator.selectedText = $selectedText
        context.coordinator.contextSentence = $contextSentence
        context.coordinator.searchManager = searchManager
        context.coordinator.savedWordsStore = savedWordsStore
        context.coordinator.requestDocumentUpdate(using: documentURL)
        context.coordinator.applyTheme(pageTheme)
        context.coordinator.refreshHighlights()
    }

    static func dismantleNSView(_ nsView: PDFView, coordinator: Coordinator) {
        coordinator.detach()
    }

    // MARK: - Layout Overlay

    /// An NSView that passes all clicks through to the view underneath.
    class PassthroughOverlayView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            // Return nil to let the event pass through to the PDFView below
            return nil
        }
    }

    // MARK: - Coordinator

    final class Coordinator {
        private weak var pdfView: PDFView?
        private var overlayView: PassthroughOverlayView?
        private var selectionObserver: NSObjectProtocol?
        private var visiblePagesObserver: NSObjectProtocol?
        private var selectionDebounceWorkItem: DispatchWorkItem?
        private var documentUpdateWorkItem: DispatchWorkItem?
        private var themeWorkItem: DispatchWorkItem?
        private var loadedDocumentURL: URL?
        private var currentTheme: PageTheme = .original
        
        var selectedText: Binding<String>
        var contextSentence: Binding<String?>
        var searchManager: PDFSearchManager
        var savedWordsStore: SavedWordsStore
        
        /// Key for identifying auto-generated highlight annotations.
        private let kAutoHighlightKey = "RELL_AutoHighlight"
        
        /// Cache of pages that have already been processed for the current set of saved words.
        private var processedPages = Set<PDFPage>()
        
        /// Track changes to saved words to trigger re-scan.
        private var lastSavedWordsCount: Int = 0
        
        init(selectedText: Binding<String>, contextSentence: Binding<String?>, searchManager: PDFSearchManager, savedWordsStore: SavedWordsStore) {
            self.selectedText = selectedText
            self.contextSentence = contextSentence
            self.searchManager = searchManager
            self.savedWordsStore = savedWordsStore
        }

        func attach(to pdfView: PDFView) {
            detach()
            self.pdfView = pdfView
            searchManager.attach(pdfView: pdfView)

            // Wire context-menu callbacks if using RELLPDFView
            if let rellView = pdfView as? RELLPDFView {
                rellView.onContextSaveWord = { [weak self] in self?.contextSaveWord() }
                rellView.onContextLookUp   = {
                    NotificationCenter.default.post(name: .inspectorRunLastModule, object: nil)
                }
                rellView.onContextCopy     = { [weak self] in self?.contextCopy() }
                rellView.onContextSpeak    = { [weak self] in self?.contextSpeak() }
            }
            
            // Create Overlay
            let overlay = PassthroughOverlayView()
            overlay.translatesAutoresizingMaskIntoConstraints = false
            pdfView.addSubview(overlay) 
            
            NSLayoutConstraint.activate([
                overlay.leadingAnchor.constraint(equalTo: pdfView.leadingAnchor),
                overlay.trailingAnchor.constraint(equalTo: pdfView.trailingAnchor),
                overlay.topAnchor.constraint(equalTo: pdfView.topAnchor),
                overlay.bottomAnchor.constraint(equalTo: pdfView.bottomAnchor)
            ])
            self.overlayView = overlay

            selectionObserver = NotificationCenter.default.addObserver(
                forName: Notification.Name.PDFViewSelectionChanged,
                object: pdfView,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                let value = pdfView.currentSelection?.string?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                self.scheduleSelectionUpdate(value)
            }
            
            visiblePagesObserver = NotificationCenter.default.addObserver(
                forName: Notification.Name.PDFViewVisiblePagesChanged,
                object: pdfView,
                queue: .main
            ) { [weak self] _ in
                self?.refreshHighlights()
            }
        }

        func requestDocumentUpdate(using url: URL?) {
            documentUpdateWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.updateDocument(using: url)
            }
            documentUpdateWorkItem = workItem
            DispatchQueue.main.async(execute: workItem)
        }

        private func updateDocument(using url: URL?) {
            guard loadedDocumentURL != url else { return }
            loadedDocumentURL = url
            if let url {
                if let doc = PDFDocument(url: url) {
                    pdfView?.document = doc
                } else {
                    AppLogger.ui.error("Failed to open PDF: \(url.lastPathComponent)")
                    pdfView?.document = nil
                }
            } else {
                pdfView?.document = nil
            }
            searchManager.clearSearch()
            scheduleSelectionUpdate("")
            
            // Re-apply theme just in case
            applyTheme(currentTheme)
            resetHighlightsCache()
        }

        private func scheduleSelectionUpdate(_ newValue: String) {
            selectionDebounceWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                
                // Extract context before updating binding
                let context = self.extractContext()
                
                Task { @MainActor in
                    if self.selectedText.wrappedValue != newValue {
                        self.selectedText.wrappedValue = newValue
                    }
                    if self.contextSentence.wrappedValue != context {
                        self.contextSentence.wrappedValue = context
                    }
                }
            }
            selectionDebounceWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
        }
        
        private func extractContext() -> String? {
            guard let pdfView = pdfView,
                  let selection = pdfView.currentSelection,
                  let page = selection.pages.first,
                  let pageText = page.string,
                  let selectionString = selection.string else {
                return nil
            }

            let cleanSelection = selectionString.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanSelection.isEmpty { return nil }

            let nsText = pageText as NSString
            let fullRange = NSRange(location: 0, length: nsText.length)

            var searchRange = fullRange
            var bestMatchRange: NSRange?

            while searchRange.location < nsText.length {
                let foundRange = nsText.range(of: cleanSelection, options: [], range: searchRange)
                if foundRange.location == NSNotFound { break }

                if let candidateSelection = page.selection(for: foundRange) {
                    let candidateBounds = candidateSelection.bounds(for: page)
                    let actualBounds = selection.bounds(for: page)

                    if candidateBounds.intersects(actualBounds) {
                        bestMatchRange = foundRange
                        break
                    }
                }

                searchRange.location = foundRange.location + foundRange.length
                searchRange.length = nsText.length - searchRange.location
            }

            // Smart Sentence Isolation fallback: for single-word selections the bounds
            // intersection may fail due to narrow glyph geometry. Fall back to the first
            // occurrence so context is always populated.
            if bestMatchRange == nil {
                let firstRange = nsText.range(of: cleanSelection, options: .caseInsensitive, range: fullRange)
                if firstRange.location != NSNotFound {
                    bestMatchRange = firstRange
                }
            }

            guard let match = bestMatchRange else { return nil }

            // Expand to sentence boundaries
            var start = match.location
            var end = match.location + match.length

            // Scan backward for sentence start
            while start > 0 {
                let charRange = NSRange(location: start - 1, length: 1)
                let char = nsText.substring(with: charRange)
                if char == "." || char == "!" || char == "?" || char == "\n" {
                    break
                }
                start -= 1
            }

            // Scan forward for sentence end
            while end < nsText.length {
                let charRange = NSRange(location: end, length: 1)
                let char = nsText.substring(with: charRange)
                if char == "." || char == "!" || char == "?" || char == "\n" {
                    end += 1 // Include the punctuation
                    break
                }
                end += 1
            }

            let sentenceRange = NSRange(location: start, length: end - start)
            let sentence = nsText.substring(with: sentenceRange)
            return sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // MARK: - Auto Highlighting
        
        func refreshHighlights(force: Bool = false) {
            guard let pdfView = pdfView else { return }
            
            var effectiveForce = force
            // If words count changed significantly, force refresh
            if savedWordsStore.words.count != lastSavedWordsCount {
                effectiveForce = true
                lastSavedWordsCount = savedWordsStore.words.count
                processedPages.removeAll()
            }
            
            let visiblePages = pdfView.visiblePages
            let savedTerms = savedWordsStore.words.map { $0.term.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            
            for page in visiblePages {
                if effectiveForce || !processedPages.contains(page) {
                    processPage(page, savedTerms: savedTerms)
                    processedPages.insert(page)
                }
            }
        }
        
        private func resetHighlightsCache() {
            processedPages.removeAll()
            refreshHighlights(force: true)
        }
        
        private func processPage(_ page: PDFPage, savedTerms: [String]) {
            removeAutoHighlights(from: page)
            
            guard !savedTerms.isEmpty, let text = page.string else { return }
            let nsText = text as NSString
            let fullRange = NSRange(location: 0, length: nsText.length)
            
            for term in savedTerms {
                var searchRange = fullRange
                while searchRange.location < nsText.length {
                    let foundRange = nsText.range(of: term, options: .caseInsensitive, range: searchRange)
                    if foundRange.location == NSNotFound { break }
                    
                    if let selection = page.selection(for: foundRange) {
                        // Handle multi-line selections
                        let lineSelections = selection.selectionsByLine()
                        for lineSel in lineSelections {
                            addHighlight(to: page, selection: lineSel)
                        }
                    }
                    
                    searchRange.location = foundRange.location + foundRange.length
                    if searchRange.location >= nsText.length { break }
                    searchRange.length = nsText.length - searchRange.location
                }
            }
        }
        
        private func addHighlight(to page: PDFPage, selection: PDFSelection) {
            let bounds = selection.bounds(for: page)
            // Skip zero-size bounds
            if bounds.width <= 0 || bounds.height <= 0 { return }
            
            let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
            annotation.color = .yellow.withAlphaComponent(0.3)
            annotation.userName = kAutoHighlightKey
            // We can also lock it so user doesn't accidentally move it, though passthrough overlay prevents clicks anyway.
            annotation.shouldPrint = false
            page.addAnnotation(annotation)
        }
        
        private func removeAutoHighlights(from page: PDFPage) {
            let annotations = page.annotations
            for annotation in annotations {
                if annotation.userName == kAutoHighlightKey {
                    page.removeAnnotation(annotation)
                }
            }
        }
        

        // MARK: - Context Menu Actions

        private func contextSaveWord() {
            guard let pdfView = pdfView,
                  let raw = pdfView.currentSelection?.string else { return }
            let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { return }

            let sentence = extractContext() ?? ""
            let filename = loadedDocumentURL?.deletingPathExtension().lastPathComponent
            let pageNum: Int?
            if let page = pdfView.currentPage {
                pageNum = (pdfView.document?.index(for: page)).map { $0 + 1 }
            } else {
                pageNum = nil
            }
            Task { @MainActor in
                self.savedWordsStore.add(SavedWord(
                    term: term,
                    sentence: sentence,
                    pdfFilename: filename,
                    pageNumber: pageNum,
                    mode: "word",
                    domain: "general",
                    llmOutputs: [:]
                ))
            }
        }

        private func contextCopy() {
            guard let text = pdfView?.currentSelection?.string, !text.isEmpty else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }

        private func contextSpeak() {
            guard let raw = pdfView?.currentSelection?.string else { return }
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            Task { @MainActor in
                SpeechManager.shared.speak(text, voice: .englishUS, rate: 0.5)
            }
        }

        // MARK: - Theme

        func applyTheme(_ theme: PageTheme) {
            currentTheme = theme
            guard let pdfView = pdfView, let overlay = overlayView else { return }

            // 1. Background Color (Void Area)
            let bgColor = theme.backgroundColor
            pdfView.wantsLayer = true
            pdfView.layer?.backgroundColor = bgColor.cgColor
            
            // 2. Overlay Configuration
            overlay.wantsLayer = true
            
            if let blendMode = theme.overlayBlendMode {
                // Color
                if let ovColor = theme.overlayColor {
                    overlay.layer?.backgroundColor = ovColor.cgColor
                } else {
                     overlay.layer?.backgroundColor = NSColor.clear.cgColor
                }
                
                // Blend Mode
                if let filter = CIFilter(name: blendMode) {
                     overlay.layer?.compositingFilter = filter
                } else {
                     overlay.layer?.compositingFilter = nil
                }
                
                overlay.isHidden = false
            } else {
                // Original Mode
                overlay.layer?.backgroundColor = NSColor.clear.cgColor
                overlay.layer?.compositingFilter = nil
                overlay.isHidden = true
            }
            
            pdfView.needsDisplay = true
        }

        func detach() {
            if let selectionObserver {
                NotificationCenter.default.removeObserver(selectionObserver)
                self.selectionObserver = nil
            }
            if let visiblePagesObserver {
                NotificationCenter.default.removeObserver(visiblePagesObserver)
                self.visiblePagesObserver = nil
            }
            selectionDebounceWorkItem?.cancel()
            selectionDebounceWorkItem = nil
            documentUpdateWorkItem?.cancel()
            documentUpdateWorkItem = nil
            themeWorkItem?.cancel()
            themeWorkItem = nil
            
            overlayView?.removeFromSuperview()
            overlayView = nil
        }

        deinit {
            detach()
        }
    }
}
