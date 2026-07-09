//
//  AnnotationsView.swift
//  Reader for Language Learner
//
//  Sidebar container merging Bookmarks, Highlights, and Notes under one tab
//  with a segmented switcher. Each segment hosts its existing view unchanged.
//

import SwiftUI

struct AnnotationsView: View {
    var bookmarkStore:   PDFBookmarkStore
    var highlightStore:  PDFHighlightStore
    var noteStore:       PDFNoteStore
    var savedWordsStore: SavedWordsStore
    var pdfViewManager:  PDFViewManager
    var currentFilename: String?
    /// Non-nil ⇒ the window is showing an EPUB; the Highlights segment
    /// switches to the EPUB-backed list (marks/notes stay PDF-only for now).
    var epubManager: EPUBViewManager? = nil
    var epubHighlightStore: EPUBHighlightStore

    enum Segment: String, CaseIterable, Identifiable {
        case bookmarks = "Marks"
        case highlights = "Highlights"
        case notes = "Notes"
        var id: String { rawValue }
    }

    @AppStorage("annotationsSegment") private var segmentRaw = Segment.bookmarks.rawValue

    private var segment: Segment {
        Segment(rawValue: segmentRaw) ?? .bookmarks
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: Binding(
                get: { segment },
                set: { segmentRaw = $0.rawValue }
            )) {
                ForEach(Segment.allCases) { segment in
                    Text(segment.rawValue).tag(segment)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.xs)

            Divider()

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        switch segment {
        case .bookmarks:
            PDFBookmarksView(
                bookmarkStore:   bookmarkStore,
                pdfViewManager:  pdfViewManager,
                currentFilename: currentFilename
            )
        case .highlights:
            if let epubManager {
                EPUBHighlightsView(
                    highlightStore: epubHighlightStore,
                    epubManager:    epubManager,
                    currentFilename: currentFilename
                )
            } else {
                HighlightsView(
                    highlightStore:  highlightStore,
                    pdfViewManager:  pdfViewManager,
                    currentFilename: currentFilename
                )
            }
        case .notes:
            PDFNotesView(
                noteStore:       noteStore,
                savedWordsStore: savedWordsStore,
                pdfViewManager:  pdfViewManager,
                currentFilename: currentFilename
            )
        }
    }
}
