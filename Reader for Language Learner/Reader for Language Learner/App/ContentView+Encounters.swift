//
//  ContentView+Encounters.swift
//  Reader for Language Learner
//
//  Feeds the encounter log (Roadmap v13 Sprint 1). A page or chapter counts
//  as read once the reader has stayed on it for a while; skimming past it
//  while scrolling or dragging the page slider doesn't.
//

import PDFKit
import SwiftUI

extension ContentView {

    /// Seconds on a PDF page / EPUB chapter before it counts as read. A
    /// chapter is longer, so it takes longer to earn.
    static let pageDwellSeconds: Double = 8
    static let chapterDwellSeconds: Double = 15

    /// Identity of the passage on screen; nil when there is none. `.task(id:)`
    /// restarts on every change, which makes the dwell timer free — moving on
    /// cancels the wait.
    var encounterPassageID: String? {
        guard let url = selectionState.documentURL, let number = currentPageNumber else { return nil }
        return "\(url.path)#\(isEPUBDocument ? "c" : "p")\(number)"
    }

    func withEncounterLog(_ content: some View) -> some View {
        content
            .task(id: encounterPassageID) {
                guard encounterPassageID != nil else { return }
                let dwell = isEPUBDocument ? Self.chapterDwellSeconds : Self.pageDwellSeconds
                try? await Task.sleep(for: .seconds(dwell))
                guard !Task.isCancelled else { return }
                recordEncounters()
            }
            .onReceive(NotificationCenter.default.publisher(for: .revealDocumentLocation)) { note in
                // Only the window already showing that document moves; one
                // being opened for it restores from `DocumentJump.prepare`.
                guard let target = note.object as? DocumentLocation,
                      selectionState.documentURL?.standardizedFileURL == target.url.standardizedFileURL
                else { return }
                if target.isEPUB {
                    epubManager.openChapter(at: target.location)
                } else {
                    pdfViewManager.goToPage(index: target.location)
                }
            }
    }

    private func recordEncounters() {
        guard let url = selectionState.documentURL, let number = currentPageNumber else { return }
        let location = number - 1
        let text: @Sendable () -> String
        let title: String
        if isEPUBDocument {
            guard let document = epubManager.document else { return }
            text = { document.plainText(at: location) }
            title = document.title.isEmpty ? url.deletingPathExtension().lastPathComponent : document.title
        } else {
            // PDFPage isn't Sendable; one page's text is read here, once.
            guard let page = pdfViewManager.pdfView?.currentPage, let string = page.string else { return }
            text = { string }
            title = url.deletingPathExtension().lastPathComponent
        }
        encounterStore.recordRead(
            text: text,
            documentPath: url.path,
            documentTitle: title,
            location: location,
            isEPUB: isEPUBDocument,
            words: savedWordsStore.words,
            language: Language.storedTarget
        )
    }
}
