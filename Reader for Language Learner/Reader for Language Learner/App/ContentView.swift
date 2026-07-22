//
//  ContentView.swift
//  Reader for Language Learner
//

import AppKit
import CoreSpotlight
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    /// The window's presented value (WindowGroup for: URL.self).
    /// nil = dashboard window; a URL = that document's window.
    @Binding var documentURL: URL?

    // Per-window state — every window gets its own document and viewer.
    @State private var selectionState   = SelectionState()
    @State private var searchManager    = PDFSearchManager()
    @State private var pdfViewManager   = PDFViewManager()
    @State private var epubManager      = EPUBViewManager()
    @State private var toastCenter      = ToastCenter()
    @State private var epubSearchManager = EPUBSearchManager()
    @State private var circuitBreaker   = CircuitBreaker()
    @State private var llmHealth        = LLMHealthMonitor()
    @State private var pageAnalysisService = PageAnalysisService()

    private var isEPUBDocument: Bool {
        selectionState.documentURL?.pathExtension.lowercased() == "epub"
    }

    private var speechManager: SpeechManager { SpeechManager.shared }

    // Shared stores — owned by the App scene, injected via environment.
    @Environment(SavedWordsStore.self)     private var savedWordsStore
    @Environment(QuickLookupService.self)  private var quickLookup
    @Environment(PDFBookmarkStore.self)    private var bookmarkStore
    @Environment(PDFNoteStore.self)        private var noteStore
    @Environment(PDFHighlightStore.self)   private var highlightStore
    @Environment(EPUBHighlightStore.self)  private var epubHighlightStore
    @Environment(EPUBBookmarkStore.self)   private var epubBookmarkStore
    @Environment(EPUBNoteStore.self)       private var epubNoteStore
    @Environment(ReadingSessionStore.self) private var sessionStore
    @Environment(RecentDocumentStore.self) private var recentDocumentStore
    @Environment(DocumentCoverStore.self)  private var coverStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showInspector = true
    @State private var isDropTargeted = false
    @State private var showWorkspaceReview = false
    @State private var showStats = false
    @State private var showReadingAppearance = false

    // Focus mode hides the side panels for distraction-free reading and
    // remembers their prior visibility so exiting restores the layout.
    @State private var focusMode = false
    @State private var preFocusSidebar = true
    @State private var preFocusInspector = true

    /// Column widths are managed (and persisted) by NavigationSplitView /
    /// .inspector themselves; only visibility is app state.
    private var showSidebar: Bool { columnVisibility != .detailOnly }

    @AppStorage("appTheme")       private var appThemeRaw:    String = AppTheme.system.rawValue
    @AppStorage("pageTheme")      private var pageThemeRaw:   String = PageTheme.original.rawValue
    @AppStorage("pdfDisplayMode") private var pdfDisplayModeRaw: String = PDFLayoutMode.single.rawValue
    @AppStorage("readingPositions") private var readingPositionsData: Data = Data()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("hoverDictionaryEnabled") private var hoverDictionaryEnabled = true
    @AppStorage("sentenceTranslationEnabled") private var sentenceTranslationEnabled = true
    @AppStorage("epubFontSize") private var epubFontSize: Double = 18
    @AppStorage(EPUBTypography.lineHeightKey) private var epubLineHeight: Double = 1.6
    @AppStorage(EPUBFontFamily.storageKey) private var epubFontFamilyRaw = EPUBFontFamily.publisher.rawValue
    @AppStorage(EPUBContentWidth.storageKey) private var epubContentWidthRaw = EPUBContentWidth.medium.rawValue
    @AppStorage(EPUBTypography.justifiedKey) private var epubJustified = false
    /// Off by default — background vocabulary pre-warming from visible page
    /// text. Every call site checks this before invoking the service.
    @AppStorage("pageAnalysisEnabled") private var pageAnalysisEnabled = false
    @AppStorage(LLMConfiguration.providerTypeKey) private var llmProviderTypeRaw: String = LLMConfiguration.defaultProviderType.rawValue
    @AppStorage(LLMConfiguration.serverURLKey)    private var llmServerURL: String = LLMConfiguration.defaultServerURL
    @AppStorage(LLMConfiguration.modelKey)        private var llmModel: String = LLMConfiguration.defaultModel

    /// Sentence the user dismissed; suppresses the strip until the selection changes.
    @State private var dismissedTranslationSentence: String = ""

    /// This view's NSWindow — used for tab preference and key-window
    /// session tracking in the multi-window world.
    @State private var hostWindow: NSWindow?

    @Environment(\.openWindow) private var openWindow

    init(documentURL: Binding<URL?>) {
        self._documentURL = documentURL
        // Users with existing reading history predate the first-run flow —
        // mark it complete before the first render so the sheet never flashes.
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "hasCompletedOnboarding"),
           let dir = FileManager.default.rellAppSupportDirectory(),
           FileManager.default.fileExists(atPath: dir.appendingPathComponent("recent_documents.json").path) {
            defaults.set(true, forKey: "hasCompletedOnboarding")
        }
    }

    private var appTheme:  AppTheme  { AppTheme(rawValue: appThemeRaw) ?? .system }
    private var pageTheme: PageTheme { PageTheme(rawValue: pageThemeRaw) ?? .original }
    private var pdfDisplayMode: PDFLayoutMode { PDFLayoutMode(rawValue: pdfDisplayModeRaw) ?? .single }
    /// Snapshot of the stored EPUB typography prefs; reading the @AppStorage
    /// properties here (not UserDefaults directly) keeps the view observing
    /// each key, so panel changes re-render the reader live.
    private var epubTypography: EPUBTypography {
        EPUBTypography(
            fontSize: epubFontSize,
            lineHeight: min(2.0, max(1.2, epubLineHeight)),
            widthEm: (EPUBContentWidth(rawValue: epubContentWidthRaw) ?? .medium).em,
            fontFamilyCSS: (EPUBFontFamily(rawValue: epubFontFamilyRaw) ?? .publisher).cssFontFamily,
            justified: epubJustified
        )
    }

    // MARK: - Body

    // Split into stages so the type checker isn't asked to solve one
    // 25-modifier expression — that alone timed out CI's clean build
    // (`the compiler is unable to type-check this expression in reasonable
    // time`) even though a warm local cache let it slide.
    var body: some View {
        withSpeechPlayback(withToast(withSheets(withDocumentAndEPUBSync(withNotifications(baseContent)))))
    }

    /// Floating playback bar while SpeechManager is speaking/paused — shared
    /// by the inspector's Speak button and Speech ▸ Read Page Aloud.
    private func withSpeechPlayback(_ content: some View) -> some View {
        content.overlay(alignment: .bottom) {
            if speechManager.state != .idle {
                SpeechPlaybackBar(manager: speechManager)
                    .padding(.bottom, DS.Spacing.xl)
                    .transition(DS.slideTransition(edge: .bottom, reduceMotion: reduceMotion))
            }
        }
        .animation(DS.Animation.respecting(DS.Animation.spring, reduceMotion: reduceMotion), value: speechManager.state)
    }

    /// Window-level toast overlay + environment injection, so any view in
    /// this window (note rows, context menus, bookmark toggle) can confirm a
    /// silent action through the shared `ToastCenter`.
    private func withToast(_ content: some View) -> some View {
        @Bindable var toastCenter = toastCenter
        return content
            .dsToast(
                isPresented: $toastCenter.isPresented,
                message: toastCenter.message,
                variant: toastCenter.variant
            )
            .environment(toastCenter)
    }

    private var baseContent: some View {
        Group {
            if selectionState.documentURL != nil {
                readerSplitView
            } else {
                NavigationStack {
                    EmptyStateView(
                        onOpenPDF: openPDF,
                        recentDocuments: recentDocumentStore.recentDocuments,
                        todayReadingTime: sessionStore.todayReadingTime,
                        reviewedTodayCount: savedWordsStore.reviewedTodayCount,
                        noteStore: noteStore,
                        savedWordsStore: savedWordsStore,
                        bookmarkStore: bookmarkStore,
                        onOpenRecent: { openDocument($0.url) },
                        onRemoveRecent: { recentDocumentStore.remove(id: $0.id) },
                        onReview: { showWorkspaceReview = true },
                        coverStore: coverStore,
                        sessionStore: sessionStore
                    )
                    .onDrop(of: [.pdf, .epub], isTargeted: $isDropTargeted, perform: handleDrop)
                    .overlay { if isDropTargeted { dropOverlay } }
                    .toolbar { toolbarContent }
                    .navigationTitle(windowTitle)
                }
            }
        }
        .focusedSceneValue(\.readerCommands, readerCommands)
        .frame(minWidth: DS.Layout.windowMin.width, minHeight: DS.Layout.windowMin.height)
        .onDrop(
            of: [.pdf, .epub],
            isTargeted: selectionState.documentURL != nil ? $isDropTargeted : nil,
            perform: handleDrop
        )
    }

    private func withNotifications(_ content: some View) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .openPDFCommand)) { _ in openPDF() }
            .onReceive(NotificationCenter.default.publisher(for: .openReviewWindowCommand)) { _ in
                openWindow(id: "review")
            }
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                      let target = SpotlightIndexer.target(from: identifier)
                else { return }
                switch target {
                case .document(let url):
                    openDocument(url)
                case .word(let id):
                    // Reveal the card: Words tab in the sidebar + detail sheet.
                    columnVisibility = .all
                    NotificationCenter.default.post(name: .revealSavedWordCommand, object: id)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .inspectorRunLastModule)) { _ in
                revealInspectorThenRepost(.inspectorRunLastModule, object: nil)
            }
            .onReceive(NotificationCenter.default.publisher(for: .inspectorRunModule)) { note in
                revealInspectorThenRepost(.inspectorRunModule, object: note.object)
            }
    }

    private func withDocumentAndEPUBSync(_ content: some View) -> some View {
        content
            .onChange(of: selectionState.documentURL) { oldURL, newURL in
                if let newURL {
                    recentDocumentStore.registerOpen(url: newURL)
                }
                // Multi-window session rule: the store tracks one active session;
                // only touch it when it belongs to (or should belong to) this window.
                if let filename = newURL?.lastPathComponent {
                    if sessionStore.activeSession?.pdfFilename != filename {
                        sessionStore.startSession(for: filename)
                    }
                } else if let old = oldURL?.lastPathComponent,
                          sessionStore.activeSession?.pdfFilename == old {
                    sessionStore.endActiveSession()
                }
                // Leaving an EPUB (close or switch to a PDF) releases the book
                // and persists its reading position.
                if newURL?.pathExtension.lowercased() != "epub", epubManager.document != nil {
                    epubManager.close()
                }
            }
            .onChange(of: documentURL) { _, newValue in
                // Window value changed from outside (restoration, openWindow) —
                // adopt it as this window's document.
                if selectionState.documentURL != newValue {
                    selectionState.documentURL = newValue
                    closeFindBar()
                    restorePageIfPDF(newValue)
                }
            }
            .onAppear {
                if let documentURL, selectionState.documentURL != documentURL {
                    selectionState.documentURL = documentURL
                    restorePageIfPDF(documentURL)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
                // Active window wins: focusing this window resumes its session.
                guard let window = note.object as? NSWindow, window === hostWindow,
                      let filename = selectionState.documentURL?.lastPathComponent,
                      sessionStore.activeSession?.pdfFilename != filename
                else { return }
                sessionStore.startSession(for: filename)
            }
            .background(WindowAccessor { window in
                hostWindow = window
                // Additional documents open as native tabs by default; users
                // can still drag a tab out into its own window.
                window.tabbingMode = .preferred
            })
            .onDisappear {
                if let filename = selectionState.documentURL?.lastPathComponent,
                   sessionStore.activeSession?.pdfFilename == filename {
                    sessionStore.endActiveSession()
                }
            }
            .task {
                recentDocumentStore.removeMissingDocuments()
                await llmHealth.check()
            }
            .onChange(of: epubManager.loadedURL) { _, url in
                // Dashboard cover: pull the book's declared cover image once.
                guard let url,
                      let document = epubManager.document,
                      let coverPath = document.coverImagePath,
                      coverStore.cover(for: url.path) == nil,
                      let resource = try? document.resource(at: coverPath)
                else { return }
                coverStore.storeCover(imageData: resource.data, for: url.path)
            }
            .onChange(of: epubManager.chapterIndex) { _, chapter in
                // Continue-reading cards track chapters the way PDFs track pages.
                guard isEPUBDocument, let url = selectionState.documentURL,
                      epubManager.chapterCount > 0 else { return }
                recentDocumentStore.updateLastPage(
                    for: url,
                    pageIndex: chapter,
                    pageCount: epubManager.chapterCount
                )
                if pageAnalysisEnabled, let text = epubManager.document?.plainText(at: chapter) {
                    pageAnalysisService.analyze(text: text, savedWordsStore: savedWordsStore, quickLookup: quickLookup)
                }
            }
            .onChange(of: llmProviderTypeRaw) { _, _ in llmHealth.scheduleCheck() }
            .onChange(of: llmServerURL)       { _, _ in llmHealth.scheduleCheck() }
            .onChange(of: llmModel)           { _, _ in llmHealth.scheduleCheck() }
            .onReceive(NotificationCenter.default.publisher(for: .llmAPIKeyChanged)) { _ in
                // Keychain-backed key has no @AppStorage to observe — settings
                // announces changes so the status light re-probes cloud providers.
                llmHealth.scheduleCheck()
            }
    }

    private func withSheets(_ content: some View) -> some View {
        content
            .sheet(item: Binding(
                get: { noteStore.draftNote },
                set: { noteStore.draftNote = $0 }
            )) { draft in
                PDFNoteEditorSheet(
                    note: draft,
                    savedWordsStore: savedWordsStore,
                    onJumpToPage: { note in
                        guard let doc = pdfViewManager.pdfView?.document,
                              note.pageIndex < doc.pageCount,
                              let page = doc.page(at: note.pageIndex)
                        else { return }
                        pdfViewManager.pdfView?.go(to: page)
                    },
                    onSave: { noteStore.saveDraft($0) },
                    onCancel: { noteStore.cancelDraft() }
                )
            }
            .sheet(isPresented: $showWorkspaceReview) {
                QuizView(
                    store: savedWordsStore,
                    onContinueReading: { showWorkspaceReview = false },
                    onClose: { showWorkspaceReview = false }
                )
                    .frame(width: 460, height: 560)
            }
            .sheet(isPresented: $showStats) {
                NavigationStack {
                    ReadingStatsView(
                        sessionStore: sessionStore,
                        savedWordsStore: savedWordsStore
                    )
                    .navigationTitle("Stats")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showStats = false }
                        }
                    }
                }
                .frame(width: 420, height: 620)
            }
            .sheet(isPresented: Binding(
                get: { !hasCompletedOnboarding },
                set: { hasCompletedOnboarding = !$0 }
            )) {
                OnboardingView { hasCompletedOnboarding = true }
                    .frame(width: 560, height: 540)
            }
    }

    // MARK: - Reader Layout (3-panel, native)

    private var readerSplitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                pdfViewManager:      pdfViewManager,
                savedWordsStore:     savedWordsStore,
                bookmarkStore:       bookmarkStore,
                noteStore:           noteStore,
                highlightStore:      highlightStore,
                currentDocumentName: currentDocumentName,
                epubManager:         isEPUBDocument ? epubManager : nil,
                epubHighlightStore:  epubHighlightStore,
                epubBookmarkStore:   epubBookmarkStore,
                epubNoteStore:       epubNoteStore
            )
            .navigationSplitViewColumnWidth(
                min: DS.Layout.sidebarMin,
                ideal: DS.Layout.sidebarDefault,
                max: 420
            )
        } detail: {
            pdfColumn
                .inspector(isPresented: $showInspector) {
                    InspectorView(
                        selectedText: selectionState.selectedText,
                        contextSentence: selectionState.contextSentence,
                        pdfFilename: selectionState.documentURL?.deletingPathExtension().lastPathComponent,
                        pageNumber: currentPageNumber,
                        savedWordsStore: savedWordsStore,
                        circuitBreaker: circuitBreaker
                    )
                    .inspectorColumnWidth(
                        min: DS.Layout.inspectorMin,
                        ideal: DS.Layout.inspectorDefault,
                        max: 640
                    )
                }
                .toolbar { toolbarContent }
                .navigationTitle(windowTitle)
                .onExitCommand { closeFindBar() }
        }
        .navigationSplitViewStyle(.balanced)
    }

    // ── Reader column (PDF or EPUB) ───────────────────────────────────
    private var pdfColumn: some View {
        VStack(spacing: DS.Spacing.sm) {
                    if !isEPUBDocument, searchManager.isFindBarVisible {
                        FindBarView(searchManager: searchManager, onClose: closeFindBar)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    if isEPUBDocument, epubSearchManager.isFindBarVisible {
                        EPUBFindBarView(
                            searchManager: epubSearchManager,
                            epubManager: epubManager,
                            onClose: closeFindBar
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    if !focusMode {
                        readerContextStrip
                    }

                    if isEPUBDocument {
                        EPUBReaderView(
                            documentURL: selectionState.documentURL,
                            manager: epubManager,
                            pageTheme: pageTheme,
                            typography: epubTypography,
                            selectedText: Binding(
                                get: { selectionState.selectedText },
                                set: { selectionState.selectedText = $0 }
                            ),
                            contextSentence: Binding(
                                get: { selectionState.contextSentence },
                                set: { selectionState.contextSentence = $0 }
                            ),
                            savedWordsStore: savedWordsStore,
                            quickLookup: quickLookup,
                            epubHighlightStore: epubHighlightStore,
                            toastCenter: toastCenter,
                            hoverEnabled: hoverDictionaryEnabled
                        )
                    } else {
                    PDFKitView(
                        documentURL: selectionState.documentURL,
                        selectedText: Binding(
                            get: { selectionState.selectedText },
                            set: { selectionState.selectedText = $0 }
                        ),
                        contextSentence: Binding(
                            get: { selectionState.contextSentence },
                            set: { selectionState.contextSentence = $0 }
                        ),
                        searchManager: searchManager,
                        pdfViewManager: pdfViewManager,
                        savedWordsStore: savedWordsStore,
                        noteStore: noteStore,
                        highlightStore: highlightStore,
                        quickLookup: quickLookup,
                        toastCenter: toastCenter,
                        hoverEnabled: hoverDictionaryEnabled,
                        pageTheme: pageTheme,
                        displayMode: pdfDisplayMode
                    )
                    .onReceive(NotificationCenter.default.publisher(for: .PDFViewPageChanged)) { notification in
                        guard let pdfView = notification.object as? PDFView,
                              let page    = pdfView.currentPage,
                              let index   = pdfView.document?.index(for: page),
                              let filename = selectionState.documentURL?.deletingPathExtension().lastPathComponent
                        else { return }
                        persistPage(index, for: filename)
                        if let currentURL = selectionState.documentURL {
                            recentDocumentStore.updateLastPage(
                                for: currentURL,
                                pageIndex: index,
                                pageCount: pdfView.document?.pageCount
                            )
                        }
                        if pageAnalysisEnabled, let text = page.string {
                            pageAnalysisService.analyze(text: text, savedWordsStore: savedWordsStore, quickLookup: quickLookup)
                        }
                    }
                    .onChange(of: selectionState.documentURL) { _, newURL in
                        guard let newURL else { return }
                        restorePage(for: newURL.deletingPathExtension().lastPathComponent)
                    }
                    }

                    if sentenceTranslationEnabled, !focusMode, let sentence = translatableSentence {
                        SentenceTranslationStrip(
                            sentence: sentence,
                            service: quickLookup,
                            onClose: { dismissedTranslationSentence = sentence }
                        )
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
        .animation(DS.Animation.standard, value: translatableSentence)
        .padding(.top, DS.Spacing.sm)
        .padding(.horizontal, DS.Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: pageTheme.backgroundColor))
    }

    /// PDF: 1-based page. EPUB: 1-based chapter — feeds the same
    /// SavedWord.pageNumber / Anki source fields.
    private var currentPageNumber: Int? {
        if isEPUBDocument {
            return epubManager.chapterCount > 0 ? epubManager.chapterIndex + 1 : nil
        }
        guard let pdfView = pdfViewManager.pdfView,
              let page    = pdfView.currentPage,
              let idx     = pdfView.document?.index(for: page)
        else { return nil }
        return idx + 1
    }

    private var currentDocumentName: String? {
        selectionState.documentURL?.deletingPathExtension().lastPathComponent
    }

    /// The selected text when it reads as a sentence (≥3 words) and hasn't
    /// been dismissed — the source for the translation strip.
    private var translatableSentence: String? {
        let selection = selectionState.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard selection.split(whereSeparator: \.isWhitespace).count >= 3 else { return nil }
        guard selection != dismissedTranslationSentence else { return nil }
        return selection
    }

    private var readerContextStrip: some View {
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
                    readerContextMetricChip(icon: "note.text", value: "\(currentNoteCount)", label: "notes")
                    readerContextMetricChip(icon: "star", value: "\(currentSavedWordCount)", label: "saved")
                    readerContextMetricChip(
                        icon: currentDueWordCount > 0 ? "clock.badge.exclamationmark" : "checkmark.seal",
                        value: "\(currentDueWordCount)",
                        label: "due",
                        tint: currentDueWordCount > 0 ? DS.Color.warning : DS.Color.success
                    )
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

    private var pageStatusText: String {
        if isEPUBDocument {
            guard epubManager.chapterCount > 0 else { return String(localized: "Opening book…") }
            let chapter = String(localized: "Chapter \(epubManager.chapterIndex + 1) / \(epubManager.chapterCount)")
            let percent = Int((epubManager.scrollFraction * 100).rounded())
            return "\(chapter) · \(percent)%"
        }
        guard pdfViewManager.pageCount > 0 else { return String(localized: "Ready") }
        if let currentPageNumber {
            return String(localized: "Page \(currentPageNumber) / \(pdfViewManager.pageCount)")
        }
        return String(localized: "\(pdfViewManager.pageCount) pages")
    }

    private var selectionSummaryText: String {
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

    private var currentNoteCount: Int {
        noteStore.count(for: currentDocumentName)
    }

    private var currentSavedWordCount: Int {
        savedWordsStore.savedCount(for: currentDocumentName)
    }

    private var currentDueWordCount: Int {
        savedWordsStore.dueCount(for: currentDocumentName)
    }

    private var readerContextDivider: some View {
        Divider()
            .frame(height: 12)
    }

    private func readerContextChip(icon: String, text: String) -> some View {
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

    private func readerContextMetricChip(
        icon: String,
        value: String,
        label: String,
        tint: Color = DS.Color.accent
    ) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: icon)
                .font(DS.Typography.icon(10, weight: .semibold))
                .foregroundStyle(tint)
            Text("\(value) \(label)")
                .lineLimit(1)
        }
        .font(DS.Typography.caption)
        .foregroundStyle(DS.Color.textSecondary)
        .padding(.horizontal, DS.Spacing.xs)
        .padding(.vertical, 3)
        .background(tint.opacity(0.08))
        .clipShape(Capsule())
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            if selectionState.documentURL != nil {
                Button(action: closeDocument) {
                    Label("Home", systemImage: "house")
                }
                .help("Close document and return to Home (⇧⌘W)")
                .accessibilityLabel("Return to Home")
            }
        }

        // NavigationSplitView supplies the system sidebar toggle.

        ToolbarItem(placement: .navigation) {
            if selectionState.documentURL != nil, !isEPUBDocument {
                PageIndicatorView(
                    currentPageIndex: pdfViewManager.currentPageIndex,
                    pageCount: pdfViewManager.pageCount
                ) { index in
                    pdfViewManager.goToPage(index: index)
                }
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: openPDF) {
                Label("Open", systemImage: "folder.badge.plus")
            }
            .help("Open a PDF or EPUB (⌘O)")

            Button(action: openFindBar) {
                Label("Find", systemImage: "magnifyingglass")
            }
            .keyboardShortcut("f", modifiers: [.command])
            .help("Find (⌘F)")
            .disabled(selectionState.documentURL == nil)

            Button(action: toggleCurrentPageBookmark) {
                Label(
                    "Bookmark",
                    systemImage: isCurrentPageBookmarked ? "bookmark.fill" : "bookmark"
                )
            }
            .keyboardShortcut("b", modifiers: [.command])
            .help(isCurrentPageBookmarked ? "Remove Bookmark (⌘B)" : "Bookmark Page (⌘B)")
            .disabled(selectionState.documentURL == nil)
        }

        ToolbarItemGroup(placement: .automatic) {
            if selectionState.documentURL != nil {
                if !isEPUBDocument {
                    zoomControls
                    Button { pdfViewManager.fitToWidth() } label: {
                        Label("Fit Width", systemImage: "arrow.left.and.right.text.vertical")
                    }
                    .help("Fit to Width (⌘0)")
                    .keyboardShortcut("0", modifiers: [.command])
                }

                // "Aa" — page theme for both formats, typography for EPUB.
                // EPUB text-size stepping keeps its ⌘+/⌘− shortcuts through
                // the View menu (ReaderCommands zoomIn/zoomOut), which was
                // already the canonical path.
                Button { showReadingAppearance.toggle() } label: {
                    Label("Reading Appearance", systemImage: "textformat.size")
                }
                .help("Reading Appearance")
                .popover(isPresented: $showReadingAppearance, arrowEdge: .bottom) {
                    ReadingAppearanceView(isEPUB: isEPUBDocument)
                }
            }
        }

        ToolbarItem(placement: .automatic) {
            Menu {
                Section("App Theme") {
                    ForEach(AppTheme.allCases) { theme in
                        Button { appThemeRaw = theme.rawValue } label: {
                            HStack {
                                Label(theme.localizedTitle, systemImage: theme.iconName)
                                if appTheme == theme { Spacer(); Image(systemName: "checkmark") }
                            }
                        }
                    }
                }
                Section("Page Theme") {
                    ForEach(PageTheme.allCases) { theme in
                        Button { pageThemeRaw = theme.rawValue } label: {
                            HStack {
                                Label(theme.localizedTitle, systemImage: theme.iconName)
                                if pageTheme == theme { Spacer(); Image(systemName: "checkmark") }
                            }
                        }
                    }
                }
            } label: {
                Label("Theme", systemImage: "paintbrush")
            }
            .help("App & Page Themes")
        }

        ToolbarItem(placement: .automatic) {
            Button { toggleFocusMode() } label: {
                Label(
                    "Focus Mode",
                    systemImage: focusMode
                        ? "arrow.down.right.and.arrow.up.left"
                        : "arrow.up.left.and.arrow.down.right"
                )
            }
            .help(focusMode ? "Exit Focus Mode (⇧⌘D)" : "Focus Mode — hide panels (⇧⌘D)")
            .disabled(selectionState.documentURL == nil)
        }

        ToolbarItem(placement: .automatic) {
            Button { showStats = true } label: {
                Label("Stats", systemImage: "chart.bar")
            }
            .help("Reading & vocabulary stats")
        }

        ToolbarItem(placement: .status) {
            LLMStatusItem(health: llmHealth, circuitBreaker: circuitBreaker)
        }

        ToolbarItem(placement: .automatic) {
            Button { toggleInspector() } label: {
                Label("Toggle Inspector", systemImage: "sidebar.right")
            }
            .help("Toggle Inspector (⌘⌥I)")
        }
    }

    private var zoomControls: some View {
        HStack(spacing: 0) {
            Button { pdfViewManager.zoomOut() } label: {
                Image(systemName: "minus")
                    .frame(width: 26, height: 22)
                    .contentShape(Rectangle())
            }
            .help("Zoom Out (⌘-)")
            .accessibilityLabel(Text("Zoom Out"))
            .keyboardShortcut("-", modifiers: [.command])

            Divider().frame(height: 16)

            Text(pdfViewManager.zoomLabel)
                .font(DS.Typography.mono)
                .foregroundStyle(DS.Color.textSecondary)
                .frame(width: 46)
                .onTapGesture { pdfViewManager.fitToWidth() }

            Divider().frame(height: 16)

            Button { pdfViewManager.zoomIn() } label: {
                Image(systemName: "plus")
                    .frame(width: 26, height: 22)
                    .contentShape(Rectangle())
            }
            .help("Zoom In (⌘+)")
            .accessibilityLabel(Text("Zoom In"))
            .keyboardShortcut("+", modifiers: [.command])
        }
        .buttonStyle(.borderless)
        .background(DS.Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.sm)
                .strokeBorder(DS.Color.separator, lineWidth: 0.5)
        )
    }

    // MARK: - Drop Overlay

    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: DS.Radius.lg)
            .strokeBorder(DS.Color.accent, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
            .background(DS.Color.accentSubtle.clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg)))
            .padding(DS.Spacing.md)
            .allowsHitTesting(false)
    }

    // MARK: - Window Title

    private var windowTitle: String {
        guard let url = selectionState.documentURL else { return "RELL" }
        if isEPUBDocument, let bookTitle = epubManager.bookTitle, !bookTitle.isEmpty {
            return bookTitle
        }
        return url.deletingPathExtension().lastPathComponent
    }

    // MARK: - Actions

    private func openPDF() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf, .epub]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openDocument(url)
    }

    private func openDocument(_ url: URL) {
        if selectionState.documentURL == nil || selectionState.documentURL == url {
            // Dashboard (or same document): this window adopts the document.
            // Setting both bindings here pre-empts the `.onChange(of:
            // documentURL)` guard below (`selectionState.documentURL` is
            // already equal to `newValue` by the time that closure runs),
            // so this is the one place that reliably sees "a document was
            // just opened in this window" for the dashboard-click path —
            // restore the reading position directly instead of relying on
            // onChange/onAppear to catch it.
            documentURL = url
            selectionState.documentURL = url
            closeFindBar()
            restorePageIfPDF(url)
        } else {
            // Another document is already on screen — open side by side
            // (a native tab by default). openWindow dedupes by URL.
            openWindow(value: url)
        }
    }

    /// Closes the current document and returns to the Home dashboard.
    /// Session end and last-page persistence are handled by the
    /// `onChange(of: selectionState.documentURL)` / page-change observers.
    private func closeDocument() {
        documentURL = nil
        selectionState.documentURL = nil
        selectionState.selectedText = ""
        selectionState.contextSentence = nil
        closeFindBar()
    }

    private func openFindBar() {
        if isEPUBDocument {
            epubSearchManager.showFindBar()
        } else {
            searchManager.showFindBar()
        }
    }

    private func closeFindBar() {
        searchManager.closeFindBar()
        epubSearchManager.closeFindBar()
    }

    /// "Find Next" — jumps to the next match of whatever query is already
    /// in the find bar. A no-op if nothing has been searched yet.
    private func findNext() {
        if isEPUBDocument {
            epubManager.findInPage(epubSearchManager.query, forward: true)
        } else {
            searchManager.next()
        }
    }

    private func findPrevious() {
        if isEPUBDocument {
            epubManager.findInPage(epubSearchManager.query, forward: false)
        } else {
            searchManager.previous()
        }
    }

    /// Menu-bar mirror of the toolbar's zoom/font-size controls — EPUB has
    /// no optical zoom, so "zoom" steps its reader font size instead.
    private func menuZoomIn() {
        if isEPUBDocument { epubFontSize = min(28, epubFontSize + 1) }
        else { pdfViewManager.zoomIn() }
    }

    private func menuZoomOut() {
        if isEPUBDocument { epubFontSize = max(12, epubFontSize - 1) }
        else { pdfViewManager.zoomOut() }
    }

    /// "Actual Size" — 100% for PDF, the default reader font size for EPUB.
    private func menuActualSize() {
        if isEPUBDocument { epubFontSize = 18 }
        else { pdfViewManager.actualSize() }
    }

    private var isCurrentTermSaved: Bool {
        let term = selectionState.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return false }
        return savedWordsStore.isSaved(
            term: term,
            pdfFilename: selectionState.documentURL?.deletingPathExtension().lastPathComponent,
            pageNumber: currentPageNumber
        )
    }

    private func toggleSidebar() {
        withAnimation(DS.Animation.respecting(DS.Animation.standard, reduceMotion: reduceMotion)) {
            columnVisibility = showSidebar ? .detailOnly : .all
        }
    }

    private func toggleInspector() {
        withAnimation(DS.Animation.respecting(DS.Animation.standard, reduceMotion: reduceMotion)) {
            showInspector.toggle()
        }
    }

    /// Enters focus mode by hiding both side panels, remembering their prior
    /// state so exiting restores exactly what was visible. Symmetric curve
    /// in both directions — entering and exiting focus mode should feel the
    /// same, not snap one way and glide the other.
    private func toggleFocusMode() {
        withAnimation(DS.Animation.respecting(DS.Animation.spring, reduceMotion: reduceMotion)) {
            if focusMode {
                focusMode = false
                columnVisibility = preFocusSidebar ? .all : .detailOnly
                showInspector = preFocusInspector
            } else {
                preFocusSidebar = showSidebar
                preFocusInspector = showInspector
                focusMode = true
                columnVisibility = .detailOnly
                showInspector = false
            }
        }
    }

    private var isCurrentPageBookmarked: Bool {
        guard let filename = selectionState.documentURL?.deletingPathExtension().lastPathComponent
        else { return false }
        if isEPUBDocument {
            return epubBookmarkStore.isBookmarked(
                filename: filename,
                chapterIndex: epubManager.chapterIndex,
                near: epubManager.scrollFraction
            )
        }
        guard let idx = currentPageNumber.map({ $0 - 1 }) else { return false }
        return bookmarkStore.isBookmarked(filename: filename, pageIndex: idx)
    }

    private func toggleCurrentPageBookmark() {
        guard let filename = selectionState.documentURL?.deletingPathExtension().lastPathComponent
        else { return }
        if isEPUBDocument {
            toggleEPUBBookmark(filename: filename)
            return
        }
        guard let pageNum = currentPageNumber else { return }
        let pageIndex = pageNum - 1
        let pageLabel = "Page \(pageNum)"
        let added = bookmarkStore.toggle(filename: filename, pageIndex: pageIndex, pageLabel: pageLabel)
        toastCenter.show(
            added ? String(localized: "Bookmark added") : String(localized: "Bookmark removed"),
            variant: .info
        )
    }

    /// EPUB path: the position is captured immediately; the snippet (first
    /// visible line, the row label) arrives async from the WebView — if an
    /// existing bookmark is near this position it's removed synchronously,
    /// otherwise the add waits for the snippet (falling back to "" on failure).
    private func toggleEPUBBookmark(filename: String) {
        let chapterIndex = epubManager.chapterIndex
        let fraction = epubManager.scrollFraction
        if let existing = epubBookmarkStore.bookmark(for: filename, chapterIndex: chapterIndex, near: fraction) {
            epubBookmarkStore.remove(id: existing.id)
            toastCenter.show(String(localized: "Bookmark removed"), variant: .info)
            return
        }
        Task {
            let snippet = await epubManager.visibleSnippet()
            // Re-check: a second ⌘B may have landed while the JS ran.
            guard epubBookmarkStore.bookmark(for: filename, chapterIndex: chapterIndex, near: fraction) == nil
            else { return }
            epubBookmarkStore.add(EPUBBookmark(
                epubFilename: filename,
                chapterIndex: chapterIndex,
                scrollFraction: fraction,
                snippet: snippet
            ))
            toastCenter.show(String(localized: "Bookmark added"), variant: .info)
        }
    }

    private func focusInspectorAndRun() {
        revealInspectorThenRepost(.inspectorRunLastModule, object: nil, forcePost: true)
    }

    private func runModule(_ module: ModuleType) {
        revealInspectorThenRepost(.inspectorRunModule, object: module.rawValue, forcePost: true)
    }

    /// Guarantees the Inspector receives a run notification even when it is
    /// hidden: unhide it first, then re-post on the next runloop turn so the
    /// freshly mounted view's `onReceive` is already subscribed. Re-entry is
    /// safe — once the panel is visible this only posts when `forcePost` is set.
    private func revealInspectorThenRepost(_ name: Notification.Name, object: Any?, forcePost: Bool = false) {
        if !showInspector {
            showInspector = true
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: name, object: object)
            }
        } else if forcePost {
            NotificationCenter.default.post(name: name, object: object)
        }
    }

    // MARK: - Menu Bar Bridge

    /// Snapshot of window state + actions published to the main menu
    /// (`ReaderMenuCommands`) through FocusedValues.
    private var readerCommands: ReaderCommands {
        ReaderCommands(
            hasDocument: selectionState.documentURL != nil,
            hasSelection: !selectionState.selectedText
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            isSidebarVisible: showSidebar,
            isInspectorVisible: showInspector,
            focusMode: focusMode,
            canGoToPreviousPage: isEPUBDocument
                ? epubManager.canGoToPreviousChapter
                : pdfViewManager.canGoToPreviousPage,
            canGoToNextPage: isEPUBDocument
                ? epubManager.canGoToNextChapter
                : pdfViewManager.canGoToNextPage,
            recentDocuments: recentDocumentStore.recentDocuments,
            isEPUBDocument: isEPUBDocument,
            isCurrentPageBookmarked: isCurrentPageBookmarked,
            isCurrentTermSaved: isCurrentTermSaved,
            pageTheme: pageTheme,
            pdfDisplayMode: pdfDisplayMode,
            speechState: speechManager.state,
            openDocument: { openDocument($0) },
            closeDocument: { closeDocument() },
            toggleSidebar: { toggleSidebar() },
            toggleInspector: { toggleInspector() },
            toggleFocusMode: { toggleFocusMode() },
            goToPreviousPage: {
                if isEPUBDocument { epubManager.previousChapter() }
                else { pdfViewManager.goToPreviousPage() }
            },
            goToNextPage: {
                if isEPUBDocument { epubManager.nextChapter() }
                else { pdfViewManager.goToNextPage() }
            },
            runModule: { runModule($0) },
            runLastModule: { focusInspectorAndRun() },
            clearRecentDocuments: { recentDocumentStore.clear() },
            showFind: { openFindBar() },
            findNext: { findNext() },
            findPrevious: { findPrevious() },
            toggleBookmark: { toggleCurrentPageBookmark() },
            toggleSaveWord: {
                revealInspectorThenRepost(.inspectorToggleSaveWord, object: nil, forcePost: true)
            },
            zoomIn: { menuZoomIn() },
            zoomOut: { menuZoomOut() },
            actualSize: { menuActualSize() },
            fitToWidth: { pdfViewManager.fitToWidth() },
            setPageTheme: { pageThemeRaw = $0.rawValue },
            setPDFDisplayMode: { pdfDisplayModeRaw = $0.rawValue },
            readAloud: { readCurrentPageAloud() },
            pauseSpeech: { speechManager.pause() },
            resumeSpeech: { speechManager.resume() },
            stopSpeech: { speechManager.stop() }
        )
    }

    /// PDF: the current page's full text. EPUB: the current chapter's
    /// (async JS-evaluated) plain text. Either way, no character cap —
    /// whole-page reads are meant to run to completion, not truncate at the
    /// 500-char default used for word/selection speak.
    private func readCurrentPageAloud() {
        if isEPUBDocument {
            Task {
                let text = await epubManager.currentChapterPlainText()
                speechManager.speakResolved(text, limit: nil)
            }
        } else {
            guard let text = pdfViewManager.pdfView?.currentPage?.string else { return }
            speechManager.speakResolved(text, limit: nil)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first,
              let type = [UTType.pdf, UTType.epub].first(where: {
                  provider.hasItemConformingToTypeIdentifier($0.identifier)
              })
        else { return false }
        provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, _ in
            let url: URL?
            if let u = item as? URL { url = u }
            else if let d = item as? Data { url = URL(dataRepresentation: d, relativeTo: nil) }
            else { url = nil }
            if let url {
                DispatchQueue.main.async {
                    openDocument(url)
                }
            }
        }
        return true
    }

    // MARK: - Reading Position Persistence

    private func persistPage(_ index: Int, for filename: String) {
        var dict = decodedPositions()
        dict[filename] = index
        readingPositionsData = (try? JSONEncoder().encode(dict)) ?? Data()
    }

    /// A window adopting its very first document (via `.onAppear` or the
    /// `documentURL` binding changing from outside) never sees
    /// `PDFKitView`'s own `.onChange(of: selectionState.documentURL)` fire —
    /// that view doesn't exist in the hierarchy yet at the moment the URL
    /// first lands, and SwiftUI never fires `.onChange` retroactively for
    /// the state change that caused a view to mount. This covers that gap;
    /// the PDFKitView-scoped `.onChange` still handles same-window switches
    /// to a different PDF once the reader is already showing.
    private func restorePageIfPDF(_ url: URL?) {
        guard let url, url.pathExtension.lowercased() != "epub" else { return }
        restorePage(for: url.deletingPathExtension().lastPathComponent)
    }

    /// Restores the saved page for a newly-opened document. Event-driven
    /// when possible: `PDFKitView.Coordinator.requestDocumentUpdate` assigns
    /// `pdfView.document` asynchronously (a `DispatchQueue.main.async` hop),
    /// which is what the old blind `Task.sleep(0.3s)` was really waiting
    /// out — PDFKit posts `.PDFViewDocumentChanged` the moment that
    /// assignment lands, so we restore right on that signal instead of
    /// guessing a delay. The 0.3s timeout always still runs as a fallback,
    /// both because the notification could in principle be unreliable and
    /// because `pdfViewManager.pdfView` itself can still be nil here (a
    /// brand-new window's `PDFKitView.makeNSView` hasn't necessarily run by
    /// the time this fires) — bailing out early in that case, instead of
    /// falling through to the timeout, is what silently broke restore on
    /// first open.
    private func restorePage(for filename: String) {
        guard let index = decodedPositions()[filename] else { return }

        var didRestore = false
        var observer: NSObjectProtocol?

        func attempt() {
            guard !didRestore,
                  let pdfView = pdfViewManager.pdfView,
                  let doc = pdfView.document,
                  index < doc.pageCount,
                  let page = doc.page(at: index)
            else { return }
            didRestore = true
            pdfView.go(to: page)
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }

        if let pdfView = pdfViewManager.pdfView {
            observer = NotificationCenter.default.addObserver(
                forName: Notification.Name.PDFViewDocumentChanged,
                object: pdfView,
                queue: .main
            ) { _ in attempt() }
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.3))
            if let observer { NotificationCenter.default.removeObserver(observer) }
            attempt()
        }
    }

    private func decodedPositions() -> [String: Int] {
        (try? JSONDecoder().decode([String: Int].self, from: readingPositionsData)) ?? [:]
    }
}

// MARK: - Window Accessor

/// Surfaces the hosting NSWindow to SwiftUI — needed for tabbing preference
/// and key-window tracking, which have no SwiftUI equivalents.
private struct WindowAccessor: NSViewRepresentable {
    var onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window { onWindow(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window { onWindow(window) }
        }
    }
}
