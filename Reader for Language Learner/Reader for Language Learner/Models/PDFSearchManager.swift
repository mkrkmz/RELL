//
//  PDFSearchManager.swift
//  Reader for Language Learner
//

import Foundation
import PDFKit

@MainActor
@Observable
final class PDFSearchManager {
    var isFindBarVisible = false
    var query: String = "" {
        didSet {
            guard !isClearing else { return }
            scheduleSearch(query)
        }
    }
    private(set) var results: [PDFSelection] = []
    private(set) var currentIndex = 0
    private(set) var isSearching = false

    private weak var pdfView: PDFView?
    private var searchTask: Task<Void, Never>?
    private var searchGeneration = 0
    private var lastHighlightSignature: [String] = []
    private var isClearing = false

    var totalCount: Int { results.count }

    var currentPositionLabel: String {
        guard !results.isEmpty else { return "0 results" }
        return "\(currentIndex + 1) of \(results.count)"
    }

    func attach(pdfView: PDFView) {
        if self.pdfView === pdfView { return }
        self.pdfView = pdfView
        lastHighlightSignature = []
        applyHighlightsIfNeeded()
    }

    func showFindBar() {
        isFindBarVisible = true
    }

    func closeFindBar() {
        isFindBarVisible = false
        clearSearch()
    }

    func clearSearch() {
        searchGeneration += 1
        searchTask?.cancel()
        isClearing = true
        query = ""
        isClearing = false
        results = []
        currentIndex = 0
        isSearching = false
        lastHighlightSignature = []
        pdfView?.highlightedSelections = nil
        pdfView?.clearSelection()
    }

    func next() {
        guard !results.isEmpty else { return }
        currentIndex = (currentIndex + 1) % results.count
        navigateToCurrentSelection()
    }

    func previous() {
        guard !results.isEmpty else { return }
        currentIndex = (currentIndex - 1 + results.count) % results.count
        navigateToCurrentSelection()
    }

    // MARK: - Private

    private func scheduleSearch(_ value: String) {
        searchTask?.cancel()
        searchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            performSearch(value)
        }
    }

    private func performSearch(_ rawQuery: String) {
        searchGeneration += 1
        let generation = searchGeneration
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            results = []
            currentIndex = 0
            isSearching = false
            lastHighlightSignature = []
            pdfView?.highlightedSelections = nil
            pdfView?.clearSelection()
            return
        }

        guard let document = pdfView?.document else {
            results = []
            currentIndex = 0
            isSearching = false
            return
        }

        isSearching = true
        let matches = document.findString(trimmed, withOptions: .caseInsensitive)

        guard generation == searchGeneration else {
            isSearching = false
            return
        }

        results = matches
        currentIndex = 0
        isSearching = false
        applyHighlightsIfNeeded()
    }

    private func applyHighlightsIfNeeded() {
        guard let pdfView else { return }
        if results.isEmpty {
            pdfView.highlightedSelections = nil
            pdfView.clearSelection()
            return
        }
        let signature = highlightSignature(for: results)
        guard signature != lastHighlightSignature else { return }
        lastHighlightSignature = signature
        pdfView.highlightedSelections = results
        navigateToCurrentSelection()
    }

    private func navigateToCurrentSelection() {
        guard let pdfView, !results.isEmpty else { return }
        let current = results[currentIndex]
        pdfView.setCurrentSelection(current, animate: true)
        pdfView.scrollSelectionToVisible(self)
    }

    private func highlightSignature(for selections: [PDFSelection]) -> [String] {
        selections.map { selection in
            let text = selection.string ?? ""
            let pageIndex = selection.pages.first.flatMap { page in
                pdfView?.document?.index(for: page)
            } ?? -1
            return "\(pageIndex)|\(text)"
        }
    }
}
