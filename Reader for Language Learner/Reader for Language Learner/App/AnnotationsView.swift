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
    /// Non-nil ⇒ the window is showing an EPUB; every segment switches to
    /// its EPUB-backed counterpart (bookmarks, highlights, and notes).
    var epubManager: EPUBViewManager? = nil
    var epubHighlightStore: EPUBHighlightStore
    var epubBookmarkStore: EPUBBookmarkStore
    var epubNoteStore: EPUBNoteStore

    enum Segment: String, CaseIterable, Identifiable {
        case bookmarks = "Marks"
        case highlights = "Highlights"
        case notes = "Notes"
        var id: String { rawValue }

        /// Raw value stays English — it keys `@AppStorage` persistence.
        var localizedTitle: String {
            switch self {
            case .bookmarks:  return String(localized: "Marks")
            case .highlights: return String(localized: "Highlights")
            case .notes:      return String(localized: "Notes")
            }
        }
    }

    @AppStorage("annotationsSegment") private var segmentRaw = Segment.bookmarks.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    Text(segment.localizedTitle).tag(segment)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.xs)

            Divider()

            content
                .id(segment)
                .transition(.opacity)
                .animation(DS.Animation.respecting(DS.Animation.fast, reduceMotion: reduceMotion), value: segment)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        switch segment {
        case .bookmarks:
            if let epubManager {
                EPUBBookmarksView(
                    bookmarkStore:   epubBookmarkStore,
                    epubManager:     epubManager,
                    currentFilename: currentFilename
                )
            } else {
                PDFBookmarksView(
                    bookmarkStore:   bookmarkStore,
                    pdfViewManager:  pdfViewManager,
                    currentFilename: currentFilename
                )
            }
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
            if let epubManager {
                EPUBNotesView(
                    noteStore:       epubNoteStore,
                    epubManager:     epubManager,
                    currentFilename: currentFilename
                )
            } else {
                PDFNotesView(
                    noteStore:       noteStore,
                    savedWordsStore: savedWordsStore,
                    pdfViewManager:  pdfViewManager,
                    currentFilename: currentFilename
                )
            }
        }
    }
}
