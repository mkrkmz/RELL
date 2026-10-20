//
//  PDFKitView+Coordinator.swift
//  Reader for Language Learner
//
//  The PDF reader's coordinator: selection, hover lookups, saved-word and
//  note highlighting, the selection bar, karaoke. Moved out of
//  PDFKitView.swift in v14 Sprint 0 — unchanged.
//

import NaturalLanguage
import os
import PDFKit
import QuartzCore
import SwiftUI

extension PDFKitView {

    // MARK: - Coordinator

    final class Coordinator {
        weak var pdfView: PDFView?
        private var overlayView: PassthroughOverlayView?
        private var selectionObserver: NSObjectProtocol?
        private var visiblePagesObserver: NSObjectProtocol?
        /// Floating action bar hosted above the live text selection (U1).
        private var selectionBarHost: NSHostingView<SelectionActionBar>?
        /// Repositions the bar as the document scrolls under a held selection.
        private var scrollBoundsObserver: NSObjectProtocol?
        private var selectionDebounceWorkItem: DispatchWorkItem?
        private var documentUpdateWorkItem: DispatchWorkItem?
        private var themeWorkItem: DispatchWorkItem?
        /// Coalesces the flood of `PDFViewVisiblePagesChanged` notifications
        /// a scroll or zoom gesture fires — without this, every single tick
        /// re-ran the highlight scan.
        var visiblePagesDebounceWorkItem: DispatchWorkItem?
        var loadedDocumentURL: URL?
        private var currentTheme: PageTheme = .original
        var currentDisplayMode: PDFLayoutMode = .single
        
        var selectedText: Binding<String>
        var contextSentence: Binding<String?>
        var searchManager: PDFSearchManager
        var savedWordsStore: SavedWordsStore
        var noteStore: PDFNoteStore
        var highlightStore: PDFHighlightStore
        var quickLookup: QuickLookupService
        var toastCenter: ToastCenter
        var hoverEnabled: Bool

        /// Key for identifying auto-generated highlight annotations.
        let kAutoHighlightKey = "RELL_AutoHighlight"
        let kNoteHighlightKey = "RELL_NoteHighlight"
        let kUserHighlightKey = "RELL_UserHighlight"
        private var highlightsObserver: NSObjectProtocol?

        // Hover dictionary
        private let hoverModel = HoverLookupModel()
        private lazy var hoverBalloon = HoverBalloon(model: hoverModel)
        private var hoverWorkItem: DispatchWorkItem?
        private var hoverTask: Task<Void, Never>?
        private var currentHoverTerm: String = ""
        
        /// Cache of pages that have already been processed for the current set of saved words.
        var processedPages = Set<PDFPage>()

        /// `page.string` re-extracts a PDF page's full text on every call —
        /// not free for a scanned or text-heavy page. Keyed by the `PDFPage`
        /// object itself (stable per document instance; NSCache's default
        /// identity-based key handling is exactly what's wanted here).
        let pageTextCache = NSCache<PDFPage, NSString>()

        /// Saved-word terms as of the last full or additive scan — diffed
        /// against the store's current terms on every refresh so a newly
        /// saved word can be layered onto already-highlighted pages instead
        /// of forcing a full teardown-and-rescan of every term.
        var knownSavedTerms: Set<String> = []
        var lastNotesCount: Int = 0

        /// Inflected shapes of saved words, per page. The pass runs off-main
        /// and lands later, so a page's literal matches are drawn first and
        /// the inflections join them on the callback's refresh.
        let inflectedTerms = InflectedTermService()
        
        init(selectedText: Binding<String>, contextSentence: Binding<String?>, searchManager: PDFSearchManager, savedWordsStore: SavedWordsStore, noteStore: PDFNoteStore, highlightStore: PDFHighlightStore, quickLookup: QuickLookupService, toastCenter: ToastCenter, hoverEnabled: Bool) {
            self.selectedText = selectedText
            self.contextSentence = contextSentence
            self.searchManager = searchManager
            self.savedWordsStore = savedWordsStore
            self.noteStore = noteStore
            self.highlightStore = highlightStore
            self.quickLookup = quickLookup
            self.toastCenter = toastCenter
            self.hoverEnabled = hoverEnabled
        }

        @MainActor func setHoverEnabled(_ enabled: Bool) {
            hoverEnabled = enabled
            if !enabled { closeHoverPopover() }
        }

        func attach(to pdfView: PDFView) {
            detach()
            self.pdfView = pdfView
            searchManager.attach(pdfView: pdfView)

            // Wire context-menu callbacks if using RELLPDFView
            if let rellView = pdfView as? RELLPDFView {
                rellView.onContextSaveWord  = { [weak self] in self?.contextSaveWord() }
                rellView.onContextAddNote   = { [weak self] in self?.contextAddNote() }
                rellView.onContextHighlight = { [weak self] color in self?.contextHighlight(color) }
                rellView.onContextLookUp    = {
                    NotificationCenter.default.post(name: .inspectorRunLastModule, object: nil)
                }
                rellView.onContextAnalyze   = { module in
                    // ContentView listens too and unhides the Inspector first
                    // when it is collapsed.
                    NotificationCenter.default.post(name: .inspectorRunModule, object: module.rawValue)
                }
                rellView.onContextCopy      = { [weak self] in self?.contextCopy() }
                rellView.onContextSpeak     = { [weak self] in self?.contextSpeak() }
                rellView.onHoverMove        = { [weak self] point in self?.handleHover(at: point) }
                rellView.onHoverExit        = { [weak self] in self?.cancelHover() }
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
            ) { [weak self, weak pdfView] _ in
                // Delivered on the main queue (`queue: .main`).
                MainActor.assumeIsolated {
                    guard let self, let pdfView else { return }
                    let value = pdfView.currentSelection?.string?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    self.scheduleSelectionUpdate(value)
                    // A deliberate selection supersedes a passive hover.
                    self.closeHoverPopover()
                }
            }
            
            visiblePagesObserver = NotificationCenter.default.addObserver(
                forName: Notification.Name.PDFViewVisiblePagesChanged,
                object: pdfView,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.scheduleVisiblePagesRefresh()
                    self?.updateSelectionBar()
                }
            }

            // Keep the selection action bar pinned above its selection while the
            // document scrolls under a held selection. PDFView scrolls an
            // internal NSScrollView; its contentView bounds change on every tick.
            if let clipView = pdfView.subviews.compactMap({ $0 as? NSScrollView }).first?.contentView {
                clipView.postsBoundsChangedNotifications = true
                scrollBoundsObserver = NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification,
                    object: clipView,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.updateSelectionBar()
                        // v18 S4: the balloon doesn't ride along with a scroll.
                        self?.cancelHover()
                    }
                }
            }

            // User highlights mutate outside SwiftUI's view-update path, so
            // re-render annotations when the store broadcasts a change.
            highlightsObserver = NotificationCenter.default.addObserver(
                forName: .pdfHighlightsChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.resetHighlightsCache()
                }
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
            pageTextCache.removeAllObjects()

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
                    self.updateSelectionBar()
                }
            }
            selectionDebounceWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
        }

        // MARK: - Selection Action Bar (U1)

        /// Shows the floating action bar above the current selection, or hides
        /// it when there is nothing selected / it scrolled out of view.
        @MainActor func updateSelectionBar() {
            guard SelectionActionBar.isEnabled,
                  let pdfView,
                  let selection = pdfView.currentSelection,
                  let raw = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty,
                  let page = selection.pages.first
            else {
                hideSelectionBar()
                return
            }

            let viewRect = pdfView.convert(selection.bounds(for: page), from: page)
            guard viewRect.width > 0, viewRect.height > 0,
                  pdfView.visibleRect.intersects(viewRect)
            else {
                hideSelectionBar()
                return
            }

            let filename = loadedDocumentURL?.deletingPathExtension().lastPathComponent
            let pageNumber = pdfView.currentPage
                .flatMap { pdfView.document?.index(for: $0) }
                .map { $0 + 1 }

            let host: NSHostingView<SelectionActionBar>
            if let existing = selectionBarHost {
                host = existing
            } else {
                host = NSHostingView(rootView: makeSelectionBar(term: raw, filename: filename, pageNumber: pageNumber))
                host.translatesAutoresizingMaskIntoConstraints = true
                pdfView.addSubview(host)
                selectionBarHost = host
            }
            host.rootView = makeSelectionBar(term: raw, filename: filename, pageNumber: pageNumber)

            let barSize = host.fittingSize
            let visible = pdfView.visibleRect

            // PDFView is not flipped (larger y is higher), so the placement
            // rule runs on mirrored y and its answer is mirrored back.
            let originX = SelectionBarPlacement.originX(selectionMidX: viewRect.midX, barWidth: barSize.width,
                                                        visibleLeft: visible.minX, visibleRight: visible.maxX)
            let mirroredTop = SelectionBarPlacement.originY(selectionTop: -viewRect.maxY, selectionBottom: -viewRect.minY,
                                                            barHeight: barSize.height,
                                                            visibleTop: -visible.maxY, visibleBottom: -visible.minY)
            let originY = -mirroredTop - barSize.height

            host.frame = CGRect(origin: CGPoint(x: originX, y: originY), size: barSize)
        }

        @MainActor private func hideSelectionBar() {
            selectionBarHost?.removeFromSuperview()
            selectionBarHost = nil
        }

        @MainActor private func makeSelectionBar(term: String, filename: String?, pageNumber: Int?) -> SelectionActionBar {
            let isSaved = savedWordsStore.isSaved(term: term, pdfFilename: filename, pageNumber: pageNumber)
            return SelectionActionBar(
                onSave: { [weak self] in
                    self?.contextSaveWord()
                    // Reflect the saved state on the bar without waiting for a
                    // reselection.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        self?.updateSelectionBar()
                    }
                },
                onAnalyze: {
                    // ContentView listens too and unhides the Inspector first.
                    NotificationCenter.default.post(name: .inspectorRunLastModule, object: nil)
                },
                onHighlight: { [weak self] color in self?.contextHighlight(color) },
                onSpeak: { [weak self] in self?.contextSpeak() },
                onCopy: { [weak self] in self?.contextCopy() },
                onSimplify: {
                    NotificationCenter.default.post(name: .simplifySelectionCommand, object: term)
                },
                onRetell: {
                    NotificationCenter.default.post(name: .retellSelectionCommand, object: term)
                },
                isPassage: GradedRewrite.isEligible(term),
                isSaved: isSaved,
                savesSentence: SavedWord.savesAsSentence(term)
            )
        }
        
        func extractContext() -> String? {
            guard let pdfView = pdfView,
                  let selection = pdfView.currentSelection,
                  let page = selection.pages.first,
                  let pageText = cachedPageString(page),
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

            // Use NLTokenizer for accurate sentence boundary detection
            let swiftText = pageText as String
            let tokenizer = NLTokenizer(unit: .sentence)
            tokenizer.string = swiftText

            // Convert NSRange to Swift String.Index
            guard let matchSwiftRange = Range(match, in: swiftText) else { return nil }

            // Find the sentence that contains the match
            let sentenceRange = tokenizer.tokenRange(for: matchSwiftRange)
            let sentence = String(swiftText[sentenceRange])
            return sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        

        // MARK: - Hover Dictionary

        private func handleHover(at point: NSPoint) {
            guard hoverEnabled, let pdfView = pdfView, pdfView.document != nil else { return }
            hoverWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.resolveHover(at: point) }
            }
            hoverWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + HoverBalloon.delay, execute: work)
        }

        @MainActor private func resolveHover(at point: NSPoint) {
            guard hoverEnabled, let pdfView = pdfView else { return }
            // Don't compete with an active text selection.
            if let active = pdfView.currentSelection?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
               !active.isEmpty {
                return
            }
            guard let page = pdfView.page(for: point, nearest: false) else {
                closeHoverPopover(); return
            }
            let pagePoint = pdfView.convert(point, to: page)
            guard let selection = page.selectionForWord(at: pagePoint),
                  let raw = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  isLikelyWord(raw)
            else {
                closeHoverPopover(); return
            }

            if raw.lowercased() == currentHoverTerm.lowercased(), hoverBalloon.isShown {
                return
            }
            currentHoverTerm = raw

            let viewRect = pdfView.convert(selection.bounds(for: page), from: page)

            let isSaved = savedWordsStore.lemmaMatchedWord(for: raw) != nil
            if !hoverModel.begin(term: raw, isSaved: isSaved,
                                 cached: quickLookup.cachedHoverAnswer(for: raw, savedWordsStore: savedWordsStore)) {
                startHoverLookup(term: raw)
            }
            showHoverPopover(relativeTo: viewRect, in: pdfView)
        }

        private func isLikelyWord(_ string: String) -> Bool {
            guard (1...40).contains(string.count) else { return false }
            if string.contains(where: { $0.isWhitespace }) { return false }
            return string.contains(where: { $0.isLetter })
        }

        @MainActor private func startHoverLookup(term: String) {
            hoverTask?.cancel()
            hoverTask = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let answer = try await self.quickLookup.hoverAnswer(for: term)
                    guard !Task.isCancelled,
                          self.currentHoverTerm.lowercased() == term.lowercased() else { return }
                    self.hoverModel.show(answer)
                } catch {
                    guard !Task.isCancelled,
                          self.currentHoverTerm.lowercased() == term.lowercased() else { return }
                    self.hoverModel.fail()
                }
            }
        }

        @MainActor private func showHoverPopover(relativeTo rect: NSRect, in view: NSView) {
            hoverBalloon.show(at: rect, in: view)
        }

        private func cancelHover() {
            hoverWorkItem?.cancel()
            closeHoverPopover()
        }

        func closeHoverPopover() {
            hoverWorkItem?.cancel()
            hoverTask?.cancel()
            currentHoverTerm = ""
            hoverBalloon.close()
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

        // MARK: - Display Mode

        /// Switches single-page ↔ two-up. PDFKit's `displayMode` setter can
        /// drop the current scroll position, so the visible page is
        /// captured first and restored with `go(to:)` right after — the
        /// user's place survives the layout change.
        func applyDisplayMode(_ mode: PDFLayoutMode) {
            guard currentDisplayMode != mode, let pdfView else {
                currentDisplayMode = mode
                return
            }
            let page = pdfView.currentPage
            currentDisplayMode = mode
            pdfView.displayMode = mode.kitDisplayMode
            if let page {
                pdfView.go(to: page)
            }
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
            if let highlightsObserver {
                NotificationCenter.default.removeObserver(highlightsObserver)
                self.highlightsObserver = nil
            }
            if let scrollBoundsObserver {
                NotificationCenter.default.removeObserver(scrollBoundsObserver)
                self.scrollBoundsObserver = nil
            }
            hideSelectionBar()
            hoverWorkItem?.cancel()
            hoverWorkItem = nil
            hoverTask?.cancel()
            hoverTask = nil
            hoverBalloon.close()
            selectionDebounceWorkItem?.cancel()
            selectionDebounceWorkItem = nil
            documentUpdateWorkItem?.cancel()
            documentUpdateWorkItem = nil
            themeWorkItem?.cancel()
            themeWorkItem = nil
            visiblePagesDebounceWorkItem?.cancel()
            visiblePagesDebounceWorkItem = nil

            overlayView?.removeFromSuperview()
            overlayView = nil
        }

        deinit {
            // SwiftUI releases coordinators on the main thread; `isolated
            // deinit` would say so, but needs a newer runtime than macOS 15.0.
            guard Thread.isMainThread else { return }
            MainActor.assumeIsolated { detach() }
        }
    }
}
