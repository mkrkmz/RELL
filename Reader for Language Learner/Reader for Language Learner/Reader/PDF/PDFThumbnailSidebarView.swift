//
//  PDFThumbnailSidebarView.swift
//  Reader for Language Learner
//

import PDFKit
import SwiftUI

/// Wraps a native `PDFThumbnailView` and connects it to the shared PDFView
/// so that clicking a thumbnail navigates the main viewer and the current page
/// is automatically highlighted.
struct PDFThumbnailSidebarView: NSViewRepresentable {
    var pdfViewManager: PDFViewManager
    var thumbnailSize: DS.ThumbnailSize

    func makeNSView(context: Context) -> PDFThumbnailView {
        let view = PDFThumbnailView()
        view.thumbnailSize = NSSize(width: thumbnailSize.width, height: thumbnailSize.height)
        view.backgroundColor = .clear
        view.allowsDragging = false
        view.allowsMultipleSelection = false

        if let pdfView = pdfViewManager.pdfView {
            view.pdfView = pdfView
        }
        return view
    }

    func updateNSView(_ nsView: PDFThumbnailView, context: Context) {
        if nsView.pdfView !== pdfViewManager.pdfView {
            nsView.pdfView = pdfViewManager.pdfView
        }
        // Resize on user preference change
        let newSize = NSSize(width: thumbnailSize.width, height: thumbnailSize.height)
        if nsView.thumbnailSize != newSize {
            nsView.thumbnailSize = newSize
        }
    }
}
