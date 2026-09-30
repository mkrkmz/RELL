//
//  ContentView+ReadingLoop.swift
//  Reader for Language Learner
//
//  The reading loop in the reader window (Roadmap v13 Sprint 2): the
//  "previously…" card above the page when you return to a book, and the
//  chapter warm-up chip in the context strip.
//

import SwiftUI

extension ContentView {

    func withReadingLoop(_ content: some View) -> some View {
        content
            .onChange(of: epubManager.loadedURL) { _, url in
                guard let url, let document = epubManager.document else { return }
                readingLoop.epubLoaded(url: url, document: document)
                openWarmUp(for: epubManager.chapterIndex)
            }
            .onChange(of: epubManager.chapterIndex) { _, chapter in
                openWarmUp(for: chapter)
            }
    }

    private func openWarmUp(for chapter: Int) {
        guard isEPUBDocument, let url = epubManager.loadedURL, let document = epubManager.document else {
            readingLoop.clearWarmUp()
            return
        }
        readingLoop.chapterOpened(
            chapter,
            bookKey: url.path,
            document: document,
            savedKeys: savedWordsStore.lemmaKeys(for: Language.storedTarget)
        )
    }

    // MARK: - Recap card

    @ViewBuilder
    var readingRecapCard: some View {
        switch readingLoop.recap {
        case .hidden:
            EmptyView()
        case .loading(let title):
            HStack(spacing: DS.Spacing.sm) {
                ProgressView().controlSize(.small)
                Text("Catching you up on \(title)…")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textSecondary)
                    .lineLimit(1)
                Spacer()
                Button("Skip") { readingLoop.dismissRecap() }
                    .buttonStyle(.link)
                    .font(DS.Typography.caption)
            }
            .dsCard(padding: DS.Spacing.sm)
            .transition(.opacity.combined(with: .move(edge: .top)))
        case .ready(let title, let text):
            RecapCard(title: title, text: text, onDismiss: { readingLoop.dismissRecap() })
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // MARK: - Warm-up chip

    @ViewBuilder
    var warmUpChip: some View {
        if case .ready(let words) = readingLoop.warmUp {
            Button {
                model.showWarmUp.toggle()
            } label: {
                Label(String(localized: "\(words.count) words to warm up"), systemImage: "sparkles")
                    .font(DS.Typography.caption.weight(.semibold))
                    .foregroundStyle(DS.Color.accent)
                    .padding(.horizontal, DS.Spacing.sm)
                    .padding(.vertical, DS.Spacing.xxs)
                    .background(DS.Color.accent.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.plain)
            .help(Text("Hard words in this chapter, before you read it"))
            .popover(isPresented: Bindable(model).showWarmUp, arrowEdge: .bottom) {
                WarmUpList(
                    words: words,
                    chapterNumber: epubManager.chapterIndex + 1,
                    isSaved: { term in savedWordsStore.lemmaMatchedWord(for: term) != nil },
                    onSave: saveWarmUpWord
                )
            }
        }
    }

    private func saveWarmUpWord(_ word: ChapterWarmUp.Word) {
        guard savedWordsStore.lemmaMatchedWord(for: word.term) == nil else { return }
        let target = Language.storedTarget
        // The definition is in whichever language the hover dictionary
        // answers in, so it goes under the module that means that.
        let module: ModuleType = HoverDictionaryLanguage.stored == .native ? .meaningTR : .definitionEN
        savedWordsStore.add(SavedWord(
            term: word.term,
            sentence: word.sentence,
            pdfFilename: currentDocumentName,
            pageNumber: currentPageNumber,
            llmOutputs: [module.rawValue: word.definition],
            language: target.rawValue
        ))
    }
}

// MARK: - Views

/// "Previously in …" — a few sentences on where the reader left off.
private struct RecapCard: View {
    let title: String
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(DS.Typography.icon(11, weight: .semibold))
                    .foregroundStyle(DS.Color.accent)
                Text("Previously in \(title)")
                    .dsOverlineLabel()
                    .textCase(.uppercase)
                    .lineLimit(1)
                Spacer()
                SpeakButton(text: text, size: 12)
                Button("Close", systemImage: "xmark") { onDismiss() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(DS.Color.textTertiary)
                    .keyboardShortcut(.cancelAction)
            }
            Text(text)
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Color.textPrimary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            HStack {
                Text("Written from the pages you read last — nothing after them.")
                    .font(DS.Typography.caption2)
                    .foregroundStyle(DS.Color.textTertiary)
                Spacer()
                Button("Continue reading", action: onDismiss)
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(DS.Spacing.md)
        .background(DS.Gradient.accentWash)
        .dsCard(padding: nil)
    }
}

/// The chapter's hard words, each with its first sentence in the chapter.
private struct WarmUpList: View {
    let words: [ChapterWarmUp.Word]
    let chapterNumber: Int
    let isSaved: (String) -> Bool
    let onSave: (ChapterWarmUp.Word) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text("Before chapter \(chapterNumber)")
                    .font(DS.Typography.headline)
                Text("Words in this chapter you may not know yet.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    ForEach(words) { word in
                        row(word)
                    }
                }
            }
            .frame(maxHeight: 420)
            HStack {
                Spacer()
                Button("Save All") {
                    for word in words where !isSaved(word.term) { onSave(word) }
                }
                .disabled(words.allSatisfy { isSaved($0.term) })
            }
        }
        .padding(DS.Spacing.lg)
        .frame(width: 380)
    }

    private func row(_ word: ChapterWarmUp.Word) -> some View {
        let saved = isSaved(word.term)
        return VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
                Text(word.term)
                    .font(DS.Typography.label.weight(.semibold))
                    .foregroundStyle(DS.Color.textPrimary)
                SpeakButton(text: word.term, size: 11)
                Spacer()
                Button {
                    onSave(word)
                } label: {
                    Label(saved ? "Saved" : "Save", systemImage: saved ? "star.fill" : "star")
                        .font(DS.Typography.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(saved ? DS.Color.star : DS.Color.accent)
                .disabled(saved)
            }
            Text(word.definition)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.textSecondary)
            if !word.sentence.isEmpty {
                Text(WordPageModel.emphasized(word.sentence, term: word.term, language: Language.storedTarget))
                    .font(DS.Typography.caption)
                    .italic()
                    .foregroundStyle(DS.Color.textTertiary)
                    .lineLimit(3)
            }
        }
        .padding(DS.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.surfaceInset)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
    }
}
