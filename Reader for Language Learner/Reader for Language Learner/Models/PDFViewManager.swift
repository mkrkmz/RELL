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
