//
//  PDFThumbnailSidebarView.swift
//  Reader for Language Learner
//

import PDFKit
import SwiftUI

/// `PDFThumbnailView` subclass adding a right-click menu for the current
/// page. PDFKit exposes no page-at-point API, so items act on the page the
/// viewer is on — titles carry the page label to make the target explicit.
final class RELLThumbnailView: PDFThumbnailView {
    var isPageBookmarked: ((Int) -> Bool)?
    var onToggleBookmark: ((Int, String) -> Void)?
    var onCopyPageText:   ((Int) -> Void)?

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let pdfView,
              let document = pdfView.document,
              let page = pdfView.currentPage
        else { return super.menu(for: event) }

        let index = document.index(for: page)
        let label = page.label.map { "Page \($0)" } ?? "Page \(index + 1)"

        let menu = NSMenu()
        menu.autoenablesItems = false

        let bookmarked = isPageBookmarked?(index) == true
        let bookmarkItem = NSMenuItem(
            title:         bookmarked ? "Remove Bookmark from \(label)" : "Bookmark \(label)",
            action:        #selector(fireToggleBookmark(_:)),
            keyEquivalent: ""
        )
        bookmarkItem.target            = self
        bookmarkItem.isEnabled         = true
        bookmarkItem.representedObject = index
        menu.addItem(bookmarkItem)

        let copyItem = NSMenuItem(
            title:         "Copy Text from \(label)",
            action:        #selector(fireCopyPageText(_:)),
            keyEquivalent: ""
        )
        copyItem.target            = self
        copyItem.isEnabled         = page.string?.isEmpty == false
        copyItem.representedObject = index
        menu.addItem(copyItem)

        return menu
    }

    @objc private func fireToggleBookmark(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int,
              let page = pdfView?.document?.page(at: index) else { return }
        let label = page.label.map { "Page \($0)" } ?? "Page \(index + 1)"
        onToggleBookmark?(index, label)
    }

    @objc private func fireCopyPageText(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int else { return }
        onCopyPageText?(index)
    }
}

/// Wraps a native `PDFThumbnailView` and connects it to the shared PDFView
/// so that clicking a thumbnail navigates the main viewer and the current page
/// is automatically highlighted.
struct PDFThumbnailSidebarView: NSViewRepresentable {
    var pdfViewManager: PDFViewManager
    var thumbnailSize: DS.ThumbnailSize
    var bookmarkStore: PDFBookmarkStore
    var currentDocumentName: String?

    func makeNSView(context: Context) -> RELLThumbnailView {
        let view = RELLThumbnailView()
        view.thumbnailSize = NSSize(width: thumbnailSize.width, height: thumbnailSize.height)
        view.backgroundColor = .clear
        view.allowsDragging = false
        view.allowsMultipleSelection = false

        if let pdfView = pdfViewManager.pdfView {
            view.pdfView = pdfView
        }
        wireContextMenu(view)
        return view
    }

    func updateNSView(_ nsView: RELLThumbnailView, context: Context) {
        if nsView.pdfView !== pdfViewManager.pdfView {
            nsView.pdfView = pdfViewManager.pdfView
        }
        // Resize on user preference change
        let newSize = NSSize(width: thumbnailSize.width, height: thumbnailSize.height)
        if nsView.thumbnailSize != newSize {
            nsView.thumbnailSize = newSize
        }
        // Re-wire so closures capture the current document name.
        wireContextMenu(nsView)
    }

    private func wireContextMenu(_ view: RELLThumbnailView) {
        let store = bookmarkStore
        let manager = pdfViewManager
        let filename = currentDocumentName

        view.isPageBookmarked = { index in
            guard let filename else { return false }
            return MainActor.assumeIsolated {
                store.isBookmarked(filename: filename, pageIndex: index)
            }
        }
        view.onToggleBookmark = { index, label in
            guard let filename else { return }
            Task { @MainActor in
                store.toggle(filename: filename, pageIndex: index, pageLabel: label)
            }
        }
        view.onCopyPageText = { index in
            Task { @MainActor in
                guard let text = manager.pdfView?.document?.page(at: index)?.string,
                      !text.isEmpty else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        }
    }
}
