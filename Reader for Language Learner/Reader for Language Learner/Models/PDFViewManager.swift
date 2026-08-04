//
//  PDFViewManager.swift
//  Reader for Language Learner
//

import PDFKit

/// Holds a shared reference to the main PDFView so that both
/// the PDF viewer and the thumbnail sidebar operate on the same instance.
@MainActor
@Observable
final class PDFViewManager {
    var pdfView: PDFView?
    var zoomLabel: String = "100%"
    var currentPageIndex: Int? = nil   // 0-based
    var pageCount: Int = 0

    private var scaleObserver: NSObjectProtocol?
    private var pageObserver:  NSObjectProtocol?

    func attach(_ pdfView: PDFView) {
        if self.pdfView === pdfView { return }
        detach()
        self.pdfView = pdfView
        scaleObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.PDFViewScaleChanged,
            object: pdfView,
            queue: .main
        ) { [weak self] _ in
            self?.updateZoomLabel()
        }
        pageObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.PDFViewPageChanged,
            object: pdfView,
            queue: .main
        ) { [weak self] _ in
            self?.updatePageInfo()
        }
        updateZoomLabel()
        updatePageInfo()
    }

    func detach() {
        if let obs = scaleObserver {
            NotificationCenter.default.removeObserver(obs)
            scaleObserver = nil
        }
        if let obs = pageObserver {
            NotificationCenter.default.removeObserver(obs)
            pageObserver = nil
        }
    }

    func goToPage(index: Int) {
        guard let doc = pdfView?.document,
              index >= 0, index < doc.pageCount,
              let page = doc.page(at: index)
        else { return }
        pdfView?.go(to: page)
    }

    var canGoToPreviousPage: Bool {
        guard let currentPageIndex else { return false }
        return currentPageIndex > 0
    }

    var canGoToNextPage: Bool {
        guard let currentPageIndex else { return false }
        return currentPageIndex < pageCount - 1
    }

    func goToPreviousPage() {
        guard pdfView?.canGoToPreviousPage == true else { return }
        pdfView?.goToPreviousPage(nil)
    }

    func goToNextPage() {
        guard pdfView?.canGoToNextPage == true else { return }
        pdfView?.goToNextPage(nil)
    }

    // MARK: Karaoke (spoken-sentence tracking)

    /// Best-effort highlight of the sentence being read aloud, by selecting it
    /// on the current page. PDF text extraction often disagrees with the
    /// tokenizer over hyphenation and line breaks, so a miss is expected and
    /// deliberately silent: the previous selection is cleared and nothing else
    /// happens. Passing nil just clears.
    ///
    /// Scoped to the current page — this follows a page being read aloud, so
    /// searching the whole document would be both slow and wrong.
    func highlightSpokenSentence(_ sentence: String?) {
        guard let pdfView, let document = pdfView.document else { return }
        guard let sentence,
              case let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.count >= 2
        else {
            pdfView.setCurrentSelection(nil, animate: false)
            return
        }

        guard let page = pdfView.currentPage else { return }
        let selections = document.findString(trimmed, withOptions: [.caseInsensitive])
        guard let match = selections.first(where: { $0.pages.contains(page) }) else {
            pdfView.setCurrentSelection(nil, animate: false)
            return
        }
        pdfView.setCurrentSelection(match, animate: false)
    }

    func zoomIn() {
        pdfView?.zoomIn(nil)
        updateZoomLabel()
    }

    func zoomOut() {
        pdfView?.zoomOut(nil)
        updateZoomLabel()
    }

    func fitToWidth() {
        guard let pdfView else { return }
        pdfView.autoScales = false
        if let page = pdfView.currentPage {
            let pageWidth = page.bounds(for: pdfView.displayBox).width
            let viewWidth = pdfView.bounds.width - 40
            if pageWidth > 0 {
                pdfView.scaleFactor = viewWidth / pageWidth
            }
        }
        updateZoomLabel()
    }

    /// Resets to 100% scale — the View menu's "Actual Size".
    func actualSize() {
        guard let pdfView else { return }
        pdfView.autoScales = false
        pdfView.scaleFactor = 1.0
        updateZoomLabel()
    }

    private func updateZoomLabel() {
        let percentage = Int((pdfView?.scaleFactor ?? 1.0) * 100)
        zoomLabel = "\(percentage)%"
    }

    private func updatePageInfo() {
        guard let pdfView, let doc = pdfView.document else {
            currentPageIndex = nil
            pageCount = 0
            return
        }
        pageCount = doc.pageCount
        if let page = pdfView.currentPage {
            currentPageIndex = doc.index(for: page)
        } else {
            currentPageIndex = nil
        }
    }
}
