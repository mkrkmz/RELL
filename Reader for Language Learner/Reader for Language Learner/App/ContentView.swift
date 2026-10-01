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
    // Lives in ReaderWindowModel; the forwarding properties below keep the
    // view code reading as it did.
    @State var model = ReaderWindowModel()
    /// Recap on return and chapter warm-up (v13 Sprint 2).
    @State var readingLoop = ReadingLoopModel()

    var selectionState: SelectionState { model.selectionState }
    var searchManager: PDFSearchManager { model.searchManager }
    var pdfViewManager: PDFViewManager { model.pdfViewManager }
    var epubManager: EPUBViewManager { model.epubManager }
    var toastCenter: ToastCenter { model.toastCenter }
    var epubSearchManager: EPUBSearchManager { model.epubSearchManager }
    var circuitBreaker: CircuitBreaker { model.circuitBreaker }
    var llmHealth: LLMHealthMonitor { model.llmHealth }
    var pageAnalysisService: PageAnalysisService { model.pageAnalysisService }
    var lexicalProfileService: LexicalProfileService { model.lexicalProfileService }
    var bookCoverageService: BookCoverageService { model.bookCoverageService }

    var isEPUBDocument: Bool { model.isEPUBDocument }

    var speechManager: SpeechManager { SpeechManager.shared }

    // Shared stores — owned by the App scene, injected via environment.
    @Environment(SavedWordsStore.self)     var savedWordsStore
    @Environment(QuickLookupService.self)  var quickLookup
    @Environment(PDFBookmarkStore.self)    var bookmarkStore
    @Environment(PDFNoteStore.self)        var noteStore
    @Environment(PDFHighlightStore.self)   var highlightStore
    @Environment(EPUBHighlightStore.self)  var epubHighlightStore
    @Environment(EPUBBookmarkStore.self)   var epubBookmarkStore
    @Environment(EPUBNoteStore.self)       var epubNoteStore
    @Environment(ReadingSessionStore.self) var sessionStore
    @Environment(RecentDocumentStore.self) var recentDocumentStore
    @Environment(DocumentCoverStore.self)  var coverStore
    @Environment(WordEncounterStore.self)  var encounterStore
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.undoManager) var undoManager

    var columnVisibility: NavigationSplitViewVisibility { model.columnVisibility }
    var showInspector: Bool {
        get { model.showInspector }
        nonmutating set { model.showInspector = newValue }
    }
    var showWorkspaceReview: Bool {
        get { model.showWorkspaceReview }
        nonmutating set { model.showWorkspaceReview = newValue }
    }
    var showStats: Bool {
        get { model.showStats }
        nonmutating set { model.showStats = newValue }
    }
    var showReadingAppearance: Bool {
        get { model.showReadingAppearance }
        nonmutating set { model.showReadingAppearance = newValue }
    }
    var isDropTargeted: Bool { model.isDropTargeted }
    var focusMode: Bool { model.focusMode }
    var zenMode: Bool { model.zenMode }
    var showSidebar: Bool { model.showSidebar }
    var chromeHidden: Bool { model.chromeHidden }

    @AppStorage(StorageKey.appTheme)       var appThemeRaw:    String = AppTheme.system.rawValue
    @AppStorage(StorageKey.pageTheme)      var pageThemeRaw:   String = PageTheme.original.rawValue
    @AppStorage(StorageKey.pdfDisplayMode) var pdfDisplayModeRaw: String = PDFLayoutMode.single.rawValue
    @AppStorage(StorageKey.hasCompletedOnboarding) var hasCompletedOnboarding = false
    @AppStorage(StorageKey.hoverDictionaryEnabled) var hoverDictionaryEnabled = true
    @AppStorage(StorageKey.sentenceTranslationEnabled) var sentenceTranslationEnabled = true
    /// Karaoke: highlight the sentence being read aloud (L4).
    @AppStorage(StorageKey.karaokeEnabled) var karaokeEnabled = true
    /// Short meanings above hard words in books (v13 Sprint 3).
    @AppStorage(StorageKey.interlinearGlossEnabled) var glossEnabled = false
    @AppStorage(StorageKey.epubFontSize) var epubFontSize: Double = 18
    @AppStorage(EPUBTypography.lineHeightKey) var epubLineHeight: Double = 1.6
    @AppStorage(EPUBFontFamily.storageKey) var epubFontFamilyRaw = EPUBFontFamily.publisher.rawValue
    @AppStorage(EPUBContentWidth.storageKey) var epubContentWidthRaw = EPUBContentWidth.medium.rawValue
    @AppStorage(EPUBTypography.justifiedKey) var epubJustified = false
    /// Off by default — background vocabulary pre-warming from visible page
    /// text. Every call site checks this before invoking the service.
    @AppStorage(StorageKey.pageAnalysisEnabled) var pageAnalysisEnabled = false
    // Observed so switching study language re-renders the saved-word
    // underlines, which are scoped to it (see `SavedWordsStore.terms(for:)`).
    @AppStorage(Language.targetLanguageKey) var targetLanguageRaw = Language.defaultTarget.rawValue
    @AppStorage(LLMConfiguration.providerTypeKey) var llmProviderTypeRaw: String = LLMConfiguration.defaultProviderType.rawValue
    @AppStorage(LLMConfiguration.serverURLKey)    var llmServerURL: String = LLMConfiguration.defaultServerURL
    @AppStorage(LLMConfiguration.modelKey)        var llmModel: String = LLMConfiguration.defaultModel

    var dismissedTranslationSentence: String {
        get { model.dismissedTranslationSentence }
        nonmutating set { model.dismissedTranslationSentence = newValue }
    }

    @Environment(\.openWindow) var openWindow

    init(documentURL: Binding<URL?>) {
        self._documentURL = documentURL
        // Users with existing reading history predate the first-run flow —
        // mark it complete before the first render so the sheet never flashes.
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: StorageKey.hasCompletedOnboarding),
           let dir = FileManager.default.rellAppSupportDirectory(),
           FileManager.default.fileExists(atPath: dir.appendingPathComponent("recent_documents.json").path) {
            defaults.set(true, forKey: StorageKey.hasCompletedOnboarding)
        }
    }

    var appTheme:  AppTheme  { AppTheme(rawValue: appThemeRaw) ?? .system }
    var pageTheme: PageTheme { PageTheme(rawValue: pageThemeRaw) ?? .original }
    var pdfDisplayMode: PDFLayoutMode { PDFLayoutMode(rawValue: pdfDisplayModeRaw) ?? .single }
    /// Snapshot of the stored EPUB typography prefs; reading the @AppStorage
    /// properties here (not UserDefaults directly) keeps the view observing
    /// each key, so panel changes re-render the reader live.
    var epubTypography: EPUBTypography {
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
        withCommandPalette(withReadingLoop(withEncounterLog(withSpeechPlayback(withToast(withSheets(withDocumentAndEPUBSync(withNotifications(baseContent))))))))
            .dataRecoveryAlert()
    }

    /// Floating playback bar while SpeechManager is speaking/paused — shared
    /// by the inspector's Speak button and Speech ▸ Read Page Aloud.
    func withSpeechPlayback(_ content: some View) -> some View {
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
    func withToast(_ content: some View) -> some View {
        @Bindable var toastCenter = toastCenter
        return content
            .dsToast(
                isPresented: $toastCenter.isPresented,
                message: toastCenter.message,
                variant: toastCenter.variant
            )
            .environment(toastCenter)
    }

    var baseContent: some View {
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
                    .onDrop(of: [.pdf, .epub], isTargeted: Bindable(model).isDropTargeted, perform: handleDrop)
                    .overlay { if isDropTargeted { dropOverlay } }
                    .toolbar { toolbarContent }
                    .navigationTitle(windowTitle)
                }
            }
        }
        .focusedSceneValue(\.readerCommands, readerCommands)
        // The reader's width minimum is the split view's own (sidebar +
        // reader + inspector minimums, ~950 pt). A fixed 900 under it let the
        // window shrink below what the columns can take, and AppKit looped
        // on the constraints — a crash at small sizes (v14 S0,
        // WindowLayoutTests). The home screen has no split view; it keeps one.
        .frame(
            minWidth: selectionState.documentURL == nil ? DS.Layout.windowMin.width : nil,
            minHeight: DS.Layout.windowMin.height
        )
        .onDrop(
            of: [.pdf, .epub],
            isTargeted: selectionState.documentURL != nil ? Bindable(model).isDropTargeted : nil,
            perform: handleDrop
        )
    }

    func withNotifications(_ content: some View) -> some View {
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
                    model.columnVisibility = .all
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

    func withDocumentAndEPUBSync(_ content: some View) -> some View {
        content
            .onChange(of: selectionState.documentURL) { oldURL, newURL in
                if let newURL {
                    // Before `registerOpen` moves `lastOpenedAt` to now — the
                    // recap needs to know how long the book sat unopened.
                    readingLoop.documentOpened(
                        url: newURL,
                        previous: recentDocumentStore.documents.first { $0.path == newURL.path }
                    )
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
                refreshBookCoverage()
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
                guard let window = note.object as? NSWindow, window === model.hostWindow,
                      let filename = selectionState.documentURL?.lastPathComponent,
                      sessionStore.activeSession?.pdfFilename != filename
                else { return }
                sessionStore.startSession(for: filename)
            }
            .background(WindowAccessor { window in
                model.hostWindow = window
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
                // The spine is parsed by now, so the book-wide pass can read
                // chapter text straight off the open document.
                refreshBookCoverage()
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
            .onChange(of: targetLanguageRaw) { _, _ in
                // The PDF reader re-scans on its own once this re-renders
                // `PDFKitView` (its term set changed); the EPUB DOM has to be
                // told, and the coverage chip's key sets moved too.
                epubManager.refreshHighlights()
                // Profiles are cached per passage, not per language.
                lexicalProfileService.invalidate()
                refreshLexicalProfile()
                refreshBookCoverage()
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

    func withSheets(_ content: some View) -> some View {
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
            .sheet(isPresented: Bindable(model).showWorkspaceReview) {
                QuizView(
                    store: savedWordsStore,
                    onContinueReading: { showWorkspaceReview = false },
                    onClose: { showWorkspaceReview = false }
                )
                    .frame(width: 460, height: 560)
            }
            .sheet(isPresented: Bindable(model).showStats) {
                NavigationStack {
                    ReadingStatsView(
                        sessionStore: sessionStore,
                        savedWordsStore: savedWordsStore,
                        recentDocumentStore: recentDocumentStore
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

    var readerSplitView: some View {
        NavigationSplitView(columnVisibility: Bindable(model).columnVisibility) {
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
                .overlay(alignment: .top) {
                    if zenMode {
                        ZenModeBar(
                            title: windowTitle,
                            subtitle: "",
                            onExit: { toggleZenMode() },
                            currentPageIndex: isEPUBDocument ? nil : pdfViewManager.currentPageIndex,
                            pageCount: isEPUBDocument ? 0 : pdfViewManager.pageCount,
                            onNavigate: isEPUBDocument ? nil : { pdfViewManager.goToPage(index: $0) },
                            controls: zenControls
                        )
                    }
                }
                .inspector(isPresented: Bindable(model).showInspector) {
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
                .toolbar(zenMode ? .hidden : .automatic, for: .windowToolbar)
                .navigationTitle(windowTitle)
                .onExitCommand { closeFindBar() }
        }
        .navigationSplitViewStyle(.balanced)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            // If the user left full-screen by the green button or ⌃⌘F, drop
            // zen chrome too so the two never disagree.
            exitZenChrome()
        }
        // Hand this window's undo manager to the annotation stores so add/
        // remove/edit are undoable (⌘Z). The stores are shared, so the focused
        // window's manager wins — correct for the common single-window case.
        .onAppear { wireUndoManagers() }
        .onChange(of: undoManager) { _, _ in wireUndoManagers() }
        // Coverage of the passage on screen (L3) — recompute as the reader
        // moves through the document or opens a different one.
        // Karaoke (L4): follow the sentence being read aloud in the document.
        .onChange(of: speechManager.spokenSentence) { _, sentence in
            guard karaokeEnabled else { return }
            if isEPUBDocument {
                epubManager.highlightSpokenSentence(sentence)
            } else {
                pdfViewManager.highlightSpokenSentence(sentence)
            }
        }
        .onChange(of: karaokeEnabled) { _, enabled in
            if !enabled {
                epubManager.highlightSpokenSentence(nil)
                pdfViewManager.highlightSpokenSentence(nil)
            }
        }
        .onChange(of: epubManager.chapterIndex) { _, _ in refreshLexicalProfile() }
        .onChange(of: currentPageNumber) { _, _ in refreshLexicalProfile() }
        .onChange(of: selectionState.documentURL) { _, _ in refreshLexicalProfile() }
    }

    // ── Reader column (PDF or EPUB) ───────────────────────────────────
    var pdfColumn: some View {
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

                    if !chromeHidden {
                        readerContextStrip
                    }

                    Group {
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
                            hoverEnabled: hoverDictionaryEnabled,
                            onFontSizeChange: { epubFontSize = $0 }
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
                    }
                    // Floats over the page rather than sitting above it: the
                    // card appearing inside this stack resized the web view
                    // under it, and the relayout loop crashed AppKit
                    // ("more Update Constraints passes than views").
                    .overlay(alignment: .top) {
                        if !chromeHidden {
                            readingRecapCard
                                .frame(maxWidth: 560)
                                .padding(DS.Spacing.md)
                                .dsShadow(DS.Shadow.float)
                        }
                    }
                    .animation(DS.Animation.standard, value: readingLoop.recap)

                    if sentenceTranslationEnabled, !chromeHidden, let sentence = translatableSentence {
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
    var currentPageNumber: Int? {
        if isEPUBDocument {
            return epubManager.chapterCount > 0 ? epubManager.chapterIndex + 1 : nil
        }
        guard let pdfView = pdfViewManager.pdfView,
              let page    = pdfView.currentPage,
              let idx     = pdfView.document?.index(for: page)
        else { return nil }
        return idx + 1
    }

    var currentDocumentName: String? {
        selectionState.documentURL?.deletingPathExtension().lastPathComponent
    }

    /// The selected text when it reads as a sentence (≥3 words) and hasn't
    /// been dismissed — the source for the translation strip.
    var translatableSentence: String? {
        let selection = selectionState.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard selection.split(whereSeparator: \.isWhitespace).count >= 3 else { return nil }
        guard selection != dismissedTranslationSentence else { return nil }
        return selection
    }

    // MARK: - Drop Overlay

    var dropOverlay: some View {
        RoundedRectangle(cornerRadius: DS.Radius.lg)
            .strokeBorder(DS.Color.accent, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
            .background(DS.Color.accentSubtle.clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg)))
            .padding(DS.Spacing.md)
            .allowsHitTesting(false)
    }

    // MARK: - Window Title

    var windowTitle: String {
        guard let url = selectionState.documentURL else { return "RELL" }
        if isEPUBDocument, let bookTitle = epubManager.bookTitle, !bookTitle.isEmpty {
            return bookTitle
        }
        return url.deletingPathExtension().lastPathComponent
    }

    // MARK: - Reading Position Persistence

    func persistPage(_ index: Int, for filename: String) {
        model.persistPage(index, for: filename)
    }

    func restorePageIfPDF(_ url: URL?) {
        model.restorePageIfPDF(url)
    }

    func restorePage(for filename: String) {
        model.restorePage(for: filename)
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
