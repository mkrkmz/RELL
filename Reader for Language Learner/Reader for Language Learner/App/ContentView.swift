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
    @State private var circuitBreaker   = CircuitBreaker()
    @State private var llmHealth        = LLMHealthMonitor()

    // Shared stores — owned by the App scene, injected via environment.
    @Environment(SavedWordsStore.self)     private var savedWordsStore
    @Environment(QuickLookupService.self)  private var quickLookup
    @Environment(PDFBookmarkStore.self)    private var bookmarkStore
    @Environment(PDFNoteStore.self)        private var noteStore
    @Environment(PDFHighlightStore.self)   private var highlightStore
    @Environment(ReadingSessionStore.self) private var sessionStore
    @Environment(RecentDocumentStore.self) private var recentDocumentStore
    @Environment(DocumentCoverStore.self)  private var coverStore

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showInspector = true
    @State private var isDropTargeted = false
    @State private var showWorkspaceReview = false
    @State private var showStats = false

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
    @AppStorage("readingPositions") private var readingPositionsData: Data = Data()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("hoverDictionaryEnabled") private var hoverDictionaryEnabled = true
    @AppStorage("sentenceTranslationEnabled") private var sentenceTranslationEnabled = true
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

    // MARK: - Body

    var body: some View {
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
                    .onDrop(of: [.pdf], isTargeted: $isDropTargeted, perform: handleDrop)
                    .overlay { if isDropTargeted { dropOverlay } }
                    .toolbar { toolbarContent }
                    .navigationTitle(windowTitle)
                }
            }
        }
        .focusedSceneValue(\.readerCommands, readerCommands)
        .frame(minWidth: DS.Layout.windowMin.width, minHeight: DS.Layout.windowMin.height)
        .preferredColorScheme(appTheme.colorScheme)
        .onDrop(
            of: [.pdf],
            isTargeted: selectionState.documentURL != nil ? $isDropTargeted : nil,
            perform: handleDrop
        )
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
        }
        .onChange(of: documentURL) { _, newValue in
            // Window value changed from outside (restoration, openWindow) —
            // adopt it as this window's document.
            if selectionState.documentURL != newValue {
                selectionState.documentURL = newValue
                closeFindBar()
            }
        }
        .onAppear {
            if let documentURL, selectionState.documentURL != documentURL {
                selectionState.documentURL = documentURL
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
        .onChange(of: llmProviderTypeRaw) { _, _ in llmHealth.scheduleCheck() }
        .onChange(of: llmServerURL)       { _, _ in llmHealth.scheduleCheck() }
        .onChange(of: llmModel)           { _, _ in llmHealth.scheduleCheck() }
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
                onContinueReading: { showWorkspaceReview = false }
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
                currentDocumentName: currentDocumentName
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

    // ── PDF Viewer column ─────────────────────────────────────────────
    private var pdfColumn: some View {
        VStack(spacing: DS.Spacing.sm) {
                    if searchManager.isFindBarVisible {
                        FindBarView(searchManager: searchManager, onClose: closeFindBar)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    if !focusMode {
                        readerContextStrip
                    }

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
                        hoverEnabled: hoverDictionaryEnabled,
                        pageTheme: pageTheme
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
                    }
                    .onChange(of: selectionState.documentURL) { _, newURL in
                        guard let newURL else { return }
                        restorePage(for: newURL.deletingPathExtension().lastPathComponent)
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

    private var currentPageNumber: Int? {
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
                text: currentDocumentName ?? "Open PDF"
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
                .strokeBorder(DS.Color.separator.opacity(0.30), lineWidth: 0.6)
        )
    }

    private var pageStatusText: String {
        guard pdfViewManager.pageCount > 0 else { return String(localized: "PDF ready") }
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
                .font(.system(size: 10, weight: .semibold))
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
                .font(.system(size: 10, weight: .semibold))
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
            if selectionState.documentURL != nil {
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
                Label("Open PDF", systemImage: "folder.badge.plus")
            }
            .help("Open PDF (⌘O)")

            Button(action: openFindBar) {
                Label("Find", systemImage: "magnifyingglass")
            }
            .keyboardShortcut("f", modifiers: [.command])
            .help("Find in PDF (⌘F)")
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
                zoomControls
                Button { pdfViewManager.fitToWidth() } label: {
                    Label("Fit Width", systemImage: "arrow.left.and.right.text.vertical")
                }
                .help("Fit to Width (⌘0)")
                .keyboardShortcut("0", modifiers: [.command])
            }
        }

        ToolbarItem(placement: .automatic) {
            Menu {
                Section("App Theme") {
                    ForEach(AppTheme.allCases) { theme in
                        Button { appThemeRaw = theme.rawValue } label: {
                            HStack {
                                Label(theme.displayName, systemImage: theme.iconName)
                                if appTheme == theme { Spacer(); Image(systemName: "checkmark") }
                            }
                        }
                    }
                }
                Section("Page Theme") {
                    ForEach(PageTheme.allCases) { theme in
                        Button { pageThemeRaw = theme.rawValue } label: {
                            HStack {
                                Label(theme.displayName, systemImage: theme.iconName)
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
        return url.deletingPathExtension().lastPathComponent
    }

    // MARK: - Actions

    private func openPDF() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openDocument(url)
    }

    private func openDocument(_ url: URL) {
        if selectionState.documentURL == nil || selectionState.documentURL == url {
            // Dashboard (or same document): this window adopts the document.
            documentURL = url
            selectionState.documentURL = url
            closeFindBar()
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
        searchManager.showFindBar()
    }

    private func closeFindBar() {
        searchManager.closeFindBar()
    }

    private func toggleSidebar() {
        columnVisibility = showSidebar ? .detailOnly : .all
    }

    private func toggleInspector() { showInspector.toggle() }

    /// Enters focus mode by hiding both side panels, remembering their prior
    /// state so exiting restores exactly what was visible.
    private func toggleFocusMode() {
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

    private var isCurrentPageBookmarked: Bool {
        guard let filename = selectionState.documentURL?.deletingPathExtension().lastPathComponent,
              let idx = currentPageNumber.map({ $0 - 1 })
        else { return false }
        return bookmarkStore.isBookmarked(filename: filename, pageIndex: idx)
    }

    private func toggleCurrentPageBookmark() {
        guard let filename = selectionState.documentURL?.deletingPathExtension().lastPathComponent,
              let pageNum = currentPageNumber else { return }
        let pageIndex = pageNum - 1
        let pageLabel = "Page \(pageNum)"
        bookmarkStore.toggle(filename: filename, pageIndex: pageIndex, pageLabel: pageLabel)
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
            canGoToPreviousPage: pdfViewManager.canGoToPreviousPage,
            canGoToNextPage: pdfViewManager.canGoToNextPage,
            recentDocuments: recentDocumentStore.recentDocuments,
            openDocument: { openDocument($0) },
            closeDocument: { closeDocument() },
            toggleSidebar: { toggleSidebar() },
            toggleInspector: { toggleInspector() },
            toggleFocusMode: { toggleFocusMode() },
            goToPreviousPage: { pdfViewManager.goToPreviousPage() },
            goToNextPage: { pdfViewManager.goToNextPage() },
            runModule: { runModule($0) },
            runLastModule: { focusInspectorAndRun() }
        )
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.pdf.identifier, options: nil) { item, _ in
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

    private func restorePage(for filename: String) {
        guard let index = decodedPositions()[filename] else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.3))
            guard let doc = pdfViewManager.pdfView?.document,
                  index < doc.pageCount,
                  let page = doc.page(at: index)
            else { return }
            pdfViewManager.pdfView?.go(to: page)
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
