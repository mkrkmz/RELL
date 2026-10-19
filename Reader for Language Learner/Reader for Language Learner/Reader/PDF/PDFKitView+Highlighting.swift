//
//  PDFKitView+Highlighting.swift
//  Reader for Language Learner
//
//  Saved-word, note and highlight marks on the PDF's pages. Split out of
//  PDFKitView+Coordinator.swift (v19 S0), unchanged.
//

import NaturalLanguage
import os
import PDFKit
import QuartzCore
import SwiftUI

extension PDFKitView.Coordinator {

        // MARK: - Auto Highlighting

        /// Coalesces same-tick visible-page-change bursts (scroll/zoom fire
        /// this notification repeatedly) into a single refresh ~120ms after
        /// the last one, rather than re-scanning on every intermediate tick.
        func scheduleVisiblePagesRefresh() {
            visiblePagesDebounceWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.refreshHighlights()
                self?.closeHoverPopover()
            }
            visiblePagesDebounceWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
        }

        @MainActor func refreshHighlights(force: Bool = false) {
            guard let pdfView = pdfView else { return }

            var effectiveForce = force
            // Additive fast path: only new terms were added since the last
            // scan, so already-processed pages just get those terms' matches
            // layered on top instead of a full teardown-and-rescan of every
            // term. Any removal or edit falls back to the original
            // clear-everything behavior below — diffing out a stale
            // highlight isn't worth the bookkeeping deletion/rename is rare.
            var additiveTerms: [String]?
            // Scoped to the study language: a library with German and
            // English words underlined both in every book before v1.36.
            let currentTerms = savedWordsStore.terms(for: Language.storedTarget)
            let currentTermSet = Set(currentTerms)
            if currentTermSet != knownSavedTerms {
                let added = currentTermSet.subtracting(knownSavedTerms)
                let removed = knownSavedTerms.subtracting(currentTermSet)
                if removed.isEmpty, !added.isEmpty {
                    additiveTerms = Array(added)
                } else {
                    effectiveForce = true
                    processedPages.removeAll()
                }
                knownSavedTerms = currentTermSet
            }
            if noteStore.notes.count != lastNotesCount {
                effectiveForce = true
                lastNotesCount = noteStore.notes.count
                processedPages.removeAll()
            }

            let visiblePages = pdfView.visiblePages
            // Early exit: nothing to layer on and every visible page is
            // already up to date — skip building the per-page term/note/
            // highlight lookups below entirely.
            guard effectiveForce || additiveTerms != nil
                    || visiblePages.contains(where: { !processedPages.contains($0) })
            else { return }

            let currentFilename = loadedDocumentURL?.deletingPathExtension().lastPathComponent ?? ""
            // Memoized in the store; computed here once rather than per page.
            let lemmaKeys = savedWordsStore.lemmaKeys(for: Language.storedTarget)
            let notesByPage = Dictionary(grouping: noteStore.notes(for: currentFilename), by: \.pageIndex)
            let highlightsByPage = Dictionary(grouping: highlightStore.highlights(for: currentFilename), by: \.pageIndex)

            for page in visiblePages {
                let pageIndex = pdfView.document?.index(for: page) ?? -1
                if let additiveTerms, processedPages.contains(page) {
                    // Only the new terms' inflections, or the page's existing
                    // highlights would be laid down a second time.
                    let addedKeys = Set(additiveTerms.map {
                        LemmaMatcher.matchKey(for: $0, language: Language.storedTarget)
                    })
                    addHighlights(
                        for: additiveTerms + inflectedForms(on: page, pageIndex: pageIndex, keys: addedKeys),
                        on: page
                    )
                    continue
                }
                if effectiveForce || !processedPages.contains(page) {
                    processPage(
                        page,
                        savedTerms: currentTerms + inflectedForms(on: page, pageIndex: pageIndex, keys: lemmaKeys),
                        notes: notesByPage[pageIndex] ?? [],
                        highlights: highlightsByPage[pageIndex] ?? []
                    )
                    processedPages.insert(page)
                }
            }
        }

        @MainActor func resetHighlightsCache() {
            processedPages.removeAll()
            refreshHighlights(force: true)
        }

        /// Returns `page.string`, computing and caching it on a miss —
        /// re-extracting a page's full text on every hover/selection/scan is
        /// the actual cost on text-heavy or scanned pages.
        func cachedPageString(_ page: PDFPage) -> String? {
            if let cached = pageTextCache.object(forKey: page) {
                return cached as String
            }
            guard let text = page.string else { return nil }
            pageTextCache.setObject(text as NSString, forKey: page)
            return text
        }

        /// Surface forms of saved vocabulary occurring on this page — "ran"
        /// and "running" for a saved "run". Empty until the page's off-main
        /// pass lands, which then forces a refresh that picks it up.
        private func inflectedForms(on page: PDFPage, pageIndex: Int, keys: Set<String>) -> [String] {
            let document = loadedDocumentURL?.lastPathComponent ?? ""
            return inflectedTerms.surfaceForms(
                passageKey: "\(document)#p\(pageIndex)",
                keys: keys,
                language: Language.storedTarget,
                text: cachedPageString(page),
                onReady: { [weak self] in self?.refreshHighlights(force: true) }
            )
        }

        private func processPage(_ page: PDFPage, savedTerms: [String], notes: [PDFNote], highlights: [PDFHighlight]) {
            removeGeneratedHighlights(from: page)

            // User highlights first so saved-word/note tints layer over them.
            for highlight in highlights {
                let nsColor = highlight.color.nsColor
                for rect in highlight.highlightRects {
                    addUserHighlight(
                        to: page,
                        rect: CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height),
                        color: nsColor
                    )
                }
            }

            addHighlights(for: savedTerms, on: page)

            for note in notes {
                for rect in note.highlightRects {
                    addNoteHighlight(
                        to: page,
                        rect: CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
                    )
                }
            }
        }

        /// Scans `page`'s text for every occurrence of each term in `terms`
        /// and adds a highlight annotation per match. Shared by `processPage`
        /// (full pass, every saved term) and the additive top-up in
        /// `refreshHighlights` (just the newly-added terms, on a page whose
        /// existing highlights are left untouched).
        private func addHighlights(for terms: [String], on page: PDFPage) {
            guard let text = cachedPageString(page) else { return }
            let nsText = text as NSString

            for term in terms {
                // Whole-word, the same rule the EPUB reader applies in JS —
                // a plain substring scan underlined "brunt" for a saved "run".
                for foundRange in TermMatcher.ranges(of: term, in: nsText) {
                    guard let selection = page.selection(for: foundRange) else { continue }
                    // Handle multi-line selections
                    for lineSel in selection.selectionsByLine() {
                        addHighlight(to: page, selection: lineSel)
                    }
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
        
        private func addNoteHighlight(to page: PDFPage, rect: CGRect) {
            guard rect.width > 0, rect.height > 0 else { return }
            let annotation = PDFAnnotation(bounds: rect, forType: .highlight, withProperties: nil)
            annotation.color = .systemBlue.withAlphaComponent(0.22)
            annotation.userName = kNoteHighlightKey
            annotation.shouldPrint = false
            page.addAnnotation(annotation)
        }

        private func addUserHighlight(to page: PDFPage, rect: CGRect, color: NSColor) {
            guard rect.width > 0, rect.height > 0 else { return }
            let annotation = PDFAnnotation(bounds: rect, forType: .highlight, withProperties: nil)
            annotation.color = color.withAlphaComponent(0.34)
            annotation.userName = kUserHighlightKey
            annotation.shouldPrint = false
            page.addAnnotation(annotation)
        }

        private func removeGeneratedHighlights(from page: PDFPage) {
            let annotations = page.annotations
            for annotation in annotations {
                if annotation.userName == kAutoHighlightKey
                    || annotation.userName == kNoteHighlightKey
                    || annotation.userName == kUserHighlightKey {
                    page.removeAnnotation(annotation)
                }
            }
        }
        
}
