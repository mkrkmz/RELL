//
//  ContentView+Comprehension.swift
//  Reader for Language Learner
//
//  The comprehension check in the reader window (Roadmap v19 Sprint 3,
//  approved mockup): a quiet offer at the end of an EPUB chapter, the check
//  from the "This chapter / This page" panel, and "Show in Book" from an
//  answer's quote. PDF pages run from where this session began.
//

import SwiftUI

extension ContentView {

    func withComprehension(_ content: some View) -> some View {
        content
            .onChange(of: epubManager.scrollFraction) { _, fraction in
                considerComprehensionOffer(at: fraction)
            }
            .onChange(of: epubManager.chapterIndex) { _, _ in
                model.comprehensionOffer = nil
            }
            .onChange(of: pdfViewManager.currentPageIndex) { _, index in
                if model.pdfSessionStartPage == nil { model.pdfSessionStartPage = index }
            }
            .onChange(of: selectionState.documentURL) { _, _ in
                model.pdfSessionStartPage = nil
                model.comprehensionOffer = nil
            }
            .sheet(item: Bindable(model).comprehensionRequest) { request in
                ComprehensionCheckSheet(request: request, onShowInBook: showInBook)
            }
    }

    // MARK: The offer at a chapter's end

    /// Once per chapter, at its end, when it's long enough to ask about —
    /// and never again once offered, checked or declined.
    func considerComprehensionOffer(at fraction: Double) {
        guard fraction >= 0.97, isEPUBDocument,
              model.comprehensionOffer == nil, model.comprehensionRequest == nil,
              UserDefaults.standard.object(forKey: StorageKey.comprehensionOfferEnabled) as? Bool ?? true,
              let url = epubManager.loadedURL, let document = epubManager.document
        else { return }
        let chapter = epubManager.chapterIndex
        let key = ComprehensionHistory.key(book: url.path, chapter: chapter)
        guard !model.comprehensionSkipKeys.contains(key) else { return }
        // Asked once per chapter: whatever the answer, not again this session.
        model.comprehensionSkipKeys.insert(key)
        guard ComprehensionHistory.entry(for: key) == nil,
              ComprehensionCheck.isLongEnough(document.plainText(at: chapter))
        else { return }
        model.comprehensionOffer = ComprehensionOffer(key: key, chapterNumber: chapter + 1)
    }

    @ViewBuilder
    var comprehensionOfferCard: some View {
        if let offer = model.comprehensionOffer, !chromeHidden {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: "checkmark.circle")
                    .font(DS.Typography.icon(16, weight: .semibold))
                    .foregroundStyle(DS.Color.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Spacing.hairline) {
                    Text("Chapter \(offer.chapterNumber) finished")
                        .font(DS.Typography.callout.weight(.semibold))
                    Text("Check what you understood with three short questions · about 3 min")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                }
                Spacer(minLength: DS.Spacing.sm)
                Button("Not Now") {
                    ComprehensionHistory.markOffered(offer.key)
                    model.comprehensionOffer = nil
                }
                .buttonStyle(.link)
                .font(DS.Typography.caption)
                Button("Start") {
                    ComprehensionHistory.markOffered(offer.key)
                    model.comprehensionOffer = nil
                    startChapterCheck(chapter: offer.chapterNumber - 1, readUpTo: 1)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(DS.Spacing.sm)
            .dsReadingOverlay(RoundedRectangle(cornerRadius: DS.Radius.md))
            .frame(maxWidth: 520)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.sm)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    // MARK: Starting a check

    /// From the chapter panel: the chapter read so far — or, at its very
    /// start, the one just finished.
    func startCurrentChapterCheck() {
        let chapter = epubManager.chapterIndex
        let fraction = epubManager.scrollFraction
        if fraction < 0.1, chapter > 0 {
            startChapterCheck(chapter: chapter - 1, readUpTo: 1)
        } else {
            startChapterCheck(chapter: chapter, readUpTo: max(fraction, 0.1))
        }
    }

    func startChapterCheck(chapter: Int, readUpTo fraction: Double) {
        guard let url = epubManager.loadedURL, let document = epubManager.document,
              chapter >= 0, chapter < document.chapterCount
        else { return }
        model.comprehensionRequest = ComprehensionCheckSheet.Request(
            title: String(localized: "Chapter \(chapter + 1)"),
            historyKey: ComprehensionHistory.key(book: url.path, chapter: chapter),
            source: .chapter(text: document.plainText(at: chapter), readUpTo: fraction)
        )
    }

    /// PDF pages, 0-based, never past the page on screen.
    func startPageCheck(_ range: ClosedRange<Int>) {
        guard let url = selectionState.documentURL else { return }
        model.comprehensionRequest = ComprehensionCheckSheet.Request(
            title: range.count == 1 ? String(localized: "Page \(range.lowerBound + 1)")
                                    : String(localized: "Pages \(range.lowerBound + 1)–\(range.upperBound + 1)"),
            historyKey: ComprehensionHistory.key(book: url.path, chapter: nil),
            source: .pages(url: url, range: range)
        )
    }

    /// What the chapter panel offers: the default PDF range, the last check.
    var comprehensionPanel: ComprehensionPanel? {
        guard let url = selectionState.documentURL else { return nil }
        if isEPUBDocument {
            guard epubManager.document != nil else { return nil }
            let key = ComprehensionHistory.key(book: url.path, chapter: epubManager.chapterIndex)
            return ComprehensionPanel(lastCheck: ComprehensionHistory.lastCheck(for: key), pdfRange: nil,
                                      onStart: { _ in startCurrentChapterCheck() })
        }
        guard let current = pdfViewManager.currentPageIndex else { return nil }
        let key = ComprehensionHistory.key(book: url.path, chapter: nil)
        return ComprehensionPanel(
            lastCheck: ComprehensionHistory.lastCheck(for: key),
            pdfRange: ComprehensionCheck.pdfRange(sessionStart: model.pdfSessionStartPage, current: current),
            onStart: { range in if let range { startPageCheck(range) } }
        )
    }

    // MARK: Show in Book

    /// The find bar, on the quote's first words — enough to find it, short
    /// enough to survive a PDF's line breaks.
    func showInBook(_ quote: String) {
        let query = quote.split(whereSeparator: \.isWhitespace).prefix(6).joined(separator: " ")
            .trimmingCharacters(in: .punctuationCharacters)
        model.openFindBar()
        if isEPUBDocument {
            epubSearchManager.query = query
            if let document = epubManager.document { epubSearchManager.runSearch(in: document) }
        } else {
            searchManager.query = query
        }
    }
}

/// The comprehension row of the chapter panel.
struct ComprehensionPanel {
    let lastCheck: ComprehensionHistory.Entry?
    /// The pages a PDF check would cover (0-based); nil for an EPUB chapter.
    let pdfRange: ClosedRange<Int>?
    let onStart: (ClosedRange<Int>?) -> Void
}

/// "Check What You Understood" in the chapter panel, with the page range
/// for a PDF: from where this session began to the page on screen, up to
/// twelve pages, never ahead.
struct ComprehensionPanelRow: View {
    let panel: ComprehensionPanel
    let onStarted: () -> Void

    @State private var first = 0

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(panel.pdfRange == nil ? "Check What You Understood in This Chapter" : "Check What You Understood")
                .font(DS.Typography.callout.weight(.semibold))
            if let range = panel.pdfRange {
                let lowest = max(0, range.upperBound - ComprehensionCheck.maxPDFPages + 1)
                Stepper(value: $first, in: lowest...range.upperBound) {
                    Text("Pages \(first + 1)–\(range.upperBound + 1)")
                        .monospacedDigit()
                }
                .controlSize(.small)
                Text("Up to \(ComprehensionCheck.maxPDFPages) pages; pages ahead of you aren't sent.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Three short questions on what you've read so far.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
            }
            HStack {
                if let last = panel.lastCheck {
                    Text("Last: \(last.understood) of \(last.total) · \(last.date.formatted(date: .abbreviated, time: .omitted))")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                }
                Spacer(minLength: DS.Spacing.sm)
                Button("Start") {
                    onStarted()
                    let range = panel.pdfRange.map { first...$0.upperBound }
                    // After the popover has closed, or the sheet can't open.
                    DispatchQueue.main.async { panel.onStart(range) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .onAppear { first = panel.pdfRange?.lowerBound ?? 0 }
    }
}
