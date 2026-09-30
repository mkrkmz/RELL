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
    var readerContextStrip: some View {
        HStack(spacing: DS.Spacing.sm) {
            readerContextChip(
                icon: "doc.text",
                text: currentDocumentName ?? "Open"
            )
            readerContextDivider
            readerContextChip(
                icon: "book.pages",
                text: pageStatusText
            )

            Spacer(minLength: DS.Spacing.sm)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.xs) {
                    warmUpChip
                    readerContextMetricChip(icon: "note.text", value: "\(currentNoteCount)", label: "notes")
                    readerContextMetricChip(icon: "star", value: "\(currentSavedWordCount)", label: "saved")
                    readerContextMetricChip(
                        icon: currentDueWordCount > 0 ? "clock.badge.exclamationmark" : "checkmark.seal",
                        value: "\(currentDueWordCount)",
                        label: "due",
                        tint: currentDueWordCount > 0 ? DS.Color.warning : DS.Color.success
                    )
                    if let profile = lexicalProfileService.current, profile.totalTokens > 0 {
                        // How much of what's on screen the reader already knows
                        // — comprehensible-input coverage (L3).
                        readerContextMetricChip(
                            icon: "percent",
                            value: "\(Int((profile.knownShare * 100).rounded()))",
                            label: "known",
                            tint: DS.Color.coverageTint(for: profile.difficulty)
                        )
                    }
                    readerContextChip(
                        icon: selectionState.selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? "cursorarrow.click"
                            : "text.cursor",
                        text: selectionSummaryText
                    )
                }
            }
            .frame(maxWidth: 360)
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, 6)
        .background(DS.Color.surfaceElevated.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.sm)
                .strokeBorder(DS.Color.hairline, lineWidth: 0.6)
        )
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

    var pageStatusText: String {
        if isEPUBDocument {
            guard epubManager.chapterCount > 0 else { return String(localized: "Opening book…") }
            let chapter = String(localized: "Chapter \(epubManager.chapterIndex + 1) / \(epubManager.chapterCount)")
            // Book-wide, content-weighted progress + time left (U3) — more
            // honest than the in-chapter scroll percentage this used to show.
            let percent = Int((epubManager.bookProgress * 100).rounded())
            let minutes = epubManager.minutesRemaining
            let tail = minutes > 0 ? String(localized: "\(percent)% · \(minutes) min left") : "\(percent)%"
            return "\(chapter) · \(tail)"
        }
        guard pdfViewManager.pageCount > 0 else { return String(localized: "Ready") }
        if let currentPageNumber {
            return String(localized: "Page \(currentPageNumber) / \(pdfViewManager.pageCount)")
        }
        return String(localized: "\(pdfViewManager.pageCount) pages")
    }

    var selectionSummaryText: String {
        let trimmedSelection = selectionState.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSelection.isEmpty else { return String(localized: "Select text to analyze") }

        let wordCount = trimmedSelection.split(whereSeparator: \.isWhitespace).count
        if wordCount <= 1 {
            return String(localized: "1 word selected")
        }
        if wordCount <= 8 {
            return String(localized: "\(wordCount) words selected")
        }
        return String(localized: "Sentence selection ready")
    }

    var currentNoteCount: Int {
        noteStore.count(for: currentDocumentName)
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

    func readerContextMetricChip(
        icon: String,
        value: String,
        label: String,
        tint: Color = DS.Color.accent
    ) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: icon)
                .font(DS.Typography.icon(10, weight: .semibold))
                .foregroundStyle(tint)
                // The adjacent text already names the metric; the glyph would
                // otherwise be announced as a second, meaningless element.
                .accessibilityHidden(true)
            Text("\(value) \(label)")
                .lineLimit(1)
        }
        .font(DS.Typography.caption)
        .foregroundStyle(DS.Color.textSecondary)
        .padding(.horizontal, DS.Spacing.xs)
        .padding(.vertical, 3)
        .background(tint.opacity(0.08))
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
    }
}
