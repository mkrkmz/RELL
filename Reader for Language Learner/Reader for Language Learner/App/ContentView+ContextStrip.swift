//
//  ContentView+ContextStrip.swift
//  Reader for Language Learner
//
//  The strip above the page: document, position, and how much of the
//  passage and the book the reader already knows.
//

import AppKit
import CoreSpotlight
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

extension ContentView {
    /// The strip's height is fixed and its content sits in an overlay, so
    /// nothing in it takes part in sizing the window. Twice it did: a
    /// horizontal scroll view, then a ViewThatFits, renegotiated with the
    /// truncating chips at narrow widths — AppKit's update-constraints loop,
    /// a crash when the window was made small (v14 S0, WindowLayoutTests).
    /// The strip's width comes from its column; how much the page status and
    /// the chapter pill show is a plain function of that width.
    var readerContextStrip: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: Self.contextStripHeight)
            .overlay {
                GeometryReader { proxy in
                    readerContextStripContent(width: proxy.size.width)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
            .dsCard(padding: nil, surface: DS.Color.surfaceElevated.opacity(0.94), radius: DS.Radius.sm)
    }

    private static let contextStripHeight: CGFloat = 30

    private func readerContextStripContent(width: CGFloat) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            readerContextChip(
                icon: "doc.text",
                text: currentDocumentName ?? "Open"
            )
            readerContextDivider
            readerContextChip(
                icon: "book.pages",
                text: pageStatusText(short: width < 520)
            )

            Spacer(minLength: DS.Spacing.sm)

            chapterPill(compact: width < 620)
        }
        .padding(.horizontal, DS.Spacing.md)
    }

    /// Profiles the whole open book against the reader's vocabulary, unless
    /// the stored snapshot still holds. Safe to call on every open: the
    /// service returns immediately when nothing has changed.
    func refreshBookCoverage() {
        guard let url = selectionState.documentURL else { return }
        let isEPUB = url.pathExtension.lowercased() == "epub"
        // An EPUB opens in two steps; wait for the archive this URL belongs to.
        if isEPUB, epubManager.loadedURL != url { return }

        bookCoverageService.refreshIfNeeded(
            url: url,
            epubDocument: isEPUB ? epubManager.document : nil,
            existing: recentDocumentStore.documents.first { $0.path == url.path }?.coverage,
            language: Language.storedTarget,
            savedWordsStore: savedWordsStore,
            onComputed: { coverage in
                recentDocumentStore.setCoverage(coverage, for: url)
            }
        )
    }

    /// Profiles the passage on screen against the reader's vocabulary. Cheap to
    /// call repeatedly — the service caches by passage and computes off-main.
    func refreshLexicalProfile() {
        guard let filename = currentDocumentName else { return }
        let language = Language.storedTarget

        if isEPUBDocument {
            let chapter = epubManager.chapterIndex
            guard epubManager.chapterCount > 0 else { return }
            Task {
                let text = await epubManager.currentChapterPlainText()
                lexicalProfileService.profile(
                    text: text,
                    cacheKey: "\(filename)#c\(chapter)",
                    language: language,
                    savedWordsStore: savedWordsStore
                )
            }
        } else {
            guard let page = pdfViewManager.pdfView?.currentPage,
                  let text = page.string,
                  let index = currentPageNumber
            else { return }
            lexicalProfileService.profile(
                text: text,
                cacheKey: "\(filename)#p\(index)",
                language: language,
                savedWordsStore: savedWordsStore
            )
        }
    }

    var pageStatusText: String { pageStatusText(short: false) }

    /// `short` drops the time left and abbreviates, for a narrow strip.
    func pageStatusText(short: Bool) -> String {
        if isEPUBDocument {
            guard epubManager.chapterCount > 0 else { return String(localized: "Opening book…") }
            let chapter = String(localized: "Chapter \(epubManager.chapterIndex + 1) / \(epubManager.chapterCount)")
            // Book-wide, content-weighted progress + time left (U3) — more
            // honest than the in-chapter scroll percentage this used to show.
            let percent = Int((epubManager.bookProgress * 100).rounded())
            let minutes = epubManager.minutesRemaining
            if short {
                return String(localized: "Ch. \(epubManager.chapterIndex + 1)/\(epubManager.chapterCount) · \(percent)%")
            }
            let tail = minutes > 0 ? String(localized: "\(percent)% · \(minutes) min left") : "\(percent)%"
            return "\(chapter) · \(tail)"
        }
        guard pdfViewManager.pageCount > 0 else { return String(localized: "Ready") }
        if let currentPageNumber {
            return String(localized: "Page \(currentPageNumber) / \(pdfViewManager.pageCount)")
        }
        return String(localized: "\(pdfViewManager.pageCount) pages")
    }

    var currentNoteCount: Int {
        isEPUBDocument ? epubNoteStore.count(for: currentDocumentName) : noteStore.count(for: currentDocumentName)
    }

    var currentSavedWordCount: Int {
        savedWordsStore.savedCount(for: currentDocumentName)
    }

    var currentDueWordCount: Int {
        savedWordsStore.dueCount(for: currentDocumentName)
    }

    var readerContextDivider: some View {
        Divider()
            .frame(height: 12)
    }

    func readerContextChip(icon: String, text: String) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: icon)
                .font(DS.Typography.icon(10, weight: .semibold))
                .foregroundStyle(DS.Color.textTertiary)

            Text(text)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(DS.Typography.caption)
        .foregroundStyle(DS.Color.textSecondary)
    }
}
