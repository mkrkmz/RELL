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
                refreshGlosses()
            }
            .onChange(of: epubManager.chapterIndex) { _, chapter in
                openWarmUp(for: chapter)
                refreshGlosses()
            }
            .onChange(of: readingLoop.warmUp) { _, _ in refreshGlosses() }
            .onChange(of: glossEnabled) { _, _ in refreshGlosses() }
            .onChange(of: savedWordsStore.words.count) { _, _ in refreshGlosses() }
            .onChange(of: readingLoop.glosses) { _, glosses in
                epubManager.setGlosses(glosses, glossOnly: readingLoop.glossOnlyTerms)
            }
            .onReceive(NotificationCenter.default.publisher(for: .simplifySelectionCommand)) { note in
                // Every window hears it; the one the reader is in answers.
                guard model.hostWindow?.isKeyWindow == true,
                      let text = note.object as? String,
                      GradedRewrite.isEligible(text)
                else { return }
                model.gradedRewriteSource = text
            }
            .onReceive(NotificationCenter.default.publisher(for: .importWebArticleCommand)) { _ in
                // With no window key (menu used from an empty desktop) the
                // first window answers rather than none.
                guard model.hostWindow?.isKeyWindow == true
                        || NSApp.keyWindow == nil && model.hostWindow == NSApp.windows.first(where: \.isVisible)
                else { return }
                model.showArticleImport = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .retellSelectionCommand)) { note in
                guard model.hostWindow?.isKeyWindow == true,
                      let text = note.object as? String,
                      GradedRewrite.isEligible(text)
                else { return }
                model.retellSource = text
            }
            .sheet(isPresented: Binding(
                get: { model.retellSource != nil },
                set: { if !$0 { model.retellSource = nil } }
            )) {
                if let source = model.retellSource {
                    RetellSheet(source: source)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .wordStoryCommand)) { _ in
                guard model.hostWindow?.isKeyWindow == true
                        || NSApp.keyWindow == nil && model.hostWindow == NSApp.windows.first(where: \.isVisible)
                else { return }
                model.showWordStory = true
            }
            .sheet(isPresented: Bindable(model).showWordStory) {
                WordStorySheet { book in openDocument(book) }
            }
            .sheet(isPresented: Bindable(model).showArticleImport) {
                ArticleImportSheet { book in openDocument(book) }
            }
            .sheet(isPresented: Binding(
                get: { model.gradedRewriteSource != nil },
                set: { if !$0 { model.gradedRewriteSource = nil } }
            )) {
                if let source = model.gradedRewriteSource {
                    GradedRewriteSheet(source: source)
                }
            }
    }

    func refreshGlosses() {
        guard isEPUBDocument, let document = epubManager.document else {
            readingLoop.refreshGlosses(enabled: false, chapter: 0, document: nil, savedWords: [])
            return
        }
        readingLoop.refreshGlosses(
            enabled: glossEnabled,
            chapter: epubManager.chapterIndex,
            document: document,
            savedWords: savedWordsStore.words
        )
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

    // MARK: - "This chapter" pill

    /// The context strip's right side (v14 S1): one pill for what concerns
    /// the passage — how much of it the reader knows, the warm-up words, the
    /// reviews due from this book — with everything in a panel on click.
    /// Before, five chips that the strip cut off at narrow widths.
    func chapterPill(compact: Bool) -> some View {
        let known = lexicalProfileService.current.flatMap { $0.totalTokens > 0 ? $0 : nil }
        let warmUpCount = warmUpWords.count
        let due = currentDueWordCount
        let needsAttention = warmUpCount > 0 || due > 0
        let scope = isEPUBDocument ? String(localized: "This chapter") : String(localized: "This page")

        return Button {
            model.showWarmUp.toggle()
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                if needsAttention {
                    Circle()
                        .fill(DS.Color.warning)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
                if !compact || known == nil {
                    Text(scope)
                }
                if let known {
                    if !compact { pillSeparator }
                    Text("\(Int((known.knownShare * 100).rounded()))%")
                        .fontWeight(.semibold)
                        .foregroundStyle(DS.Color.coverageTint(for: known.difficulty))
                }
                if !compact, warmUpCount > 0 {
                    pillSeparator
                    Text("\(warmUpCount) warm-up")
                }
                if !compact, due > 0 {
                    pillSeparator
                    Text("\(due) due")
                }
                Image(systemName: "chevron.down")
                    .font(DS.Typography.icon(8, weight: .semibold))
                    .foregroundStyle(DS.Color.textTertiary)
                    .accessibilityHidden(true)
            }
            .font(DS.Typography.caption.weight(.medium))
            .foregroundStyle(DS.Color.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, 3)
            .background(DS.Color.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(DS.Color.hairline, lineWidth: 0.6))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(Text("What you know here, words to warm up, and reviews due"))
        .accessibilityLabel(scope)
        .popover(isPresented: Bindable(model).showWarmUp, arrowEdge: .bottom) {
            ChapterPanel(
                title: isEPUBDocument
                    ? String(localized: "Chapter \(epubManager.chapterIndex + 1)")
                    : pageStatusText,
                known: known,
                warmUpWords: warmUpWords,
                chapterNumber: epubManager.chapterIndex + 1,
                due: due,
                notes: currentNoteCount,
                saved: currentSavedWordCount,
                isSaved: { term in savedWordsStore.lemmaMatchedWord(for: term) != nil },
                onSave: saveWarmUpWord
            )
        }
    }

    private var warmUpWords: [ChapterWarmUp.Word] {
        if case .ready(let words) = readingLoop.warmUp { return words }
        return []
    }

    private var pillSeparator: some View {
        Text("·").foregroundStyle(DS.Color.textTertiary).accessibilityHidden(true)
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
            language: target.rawValue,
            documentPath: selectionState.documentURL?.path
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
struct WarmUpList: View {
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

/// The panel behind the "This chapter" pill: every number the strip used to
/// show, and the warm-up list one click further.
private struct ChapterPanel: View {
    let title: String
    let known: LexicalProfile?
    let warmUpWords: [ChapterWarmUp.Word]
    let chapterNumber: Int
    let due: Int
    let notes: Int
    let saved: Int
    let isSaved: (String) -> Bool
    let onSave: (ChapterWarmUp.Word) -> Void

    @State private var showingWords = false

    var body: some View {
        if showingWords {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    showingWords = false
                } label: {
                    Label("Back to Overview", systemImage: "chevron.left")
                        .font(DS.Typography.caption)
                }
                .buttonStyle(.borderless)
                .padding([.top, .horizontal], DS.Spacing.md)
                WarmUpList(words: warmUpWords, chapterNumber: chapterNumber, isSaved: isSaved, onSave: onSave)
            }
        } else {
            summary
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text(title)
                .font(DS.Typography.headline)

            if let known {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    row("Words you know") {
                        Text("\(Int((known.knownShare * 100).rounded()))%")
                            .foregroundStyle(DS.Color.coverageTint(for: known.difficulty))
                    }
                    ProgressView(value: known.knownShare)
                        .tint(DS.Color.coverageTint(for: known.difficulty))
                }
            }

            if !warmUpWords.isEmpty {
                row("Warm-up: hard words here") {
                    Button("See \(warmUpWords.count) words") { showingWords = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }

            row("Reviews due from this book") {
                Text("\(due)")
                    .foregroundStyle(due > 0 ? DS.Color.warning : DS.Color.textSecondary)
            }

            Divider()

            row("Notes") { Text("\(notes)") }
            row("Saved words") { Text("\(saved)") }
        }
        .font(DS.Typography.callout)
        .padding(DS.Spacing.lg)
        .frame(width: 300)
    }

    private func row(_ label: LocalizedStringKey, @ViewBuilder value: () -> some View) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(DS.Color.textSecondary)
            Spacer(minLength: DS.Spacing.sm)
            value()
                .fontWeight(.semibold)
                .monospacedDigit()
        }
    }
}
