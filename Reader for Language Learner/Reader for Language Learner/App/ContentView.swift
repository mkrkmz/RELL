//
//  ContentView.swift
//  Reader for Language Learner
//

import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var selectionState   = SelectionState()
    @State private var searchManager    = PDFSearchManager()
    @State private var pdfViewManager   = PDFViewManager()
    @State private var savedWordsStore  = SavedWordsStore()
    @State private var bookmarkStore    = PDFBookmarkStore()
    @State private var sessionStore     = ReadingSessionStore()
    @State private var ankiPrefs        = AnkiModulePreferences()

    @State private var showSidebar   = true
    @State private var showInspector = true
    @State private var isDropTargeted = false

    @AppStorage("sidebarWidth")   private var sidebarWidth:   Double = DS.Layout.sidebarDefault
    @AppStorage("inspectorWidth") private var inspectorWidth: Double = DS.Layout.inspectorDefault
    @AppStorage("appTheme")       private var appThemeRaw:    String = AppTheme.system.rawValue
    @AppStorage("pageTheme")      private var pageThemeRaw:   String = PageTheme.original.rawValue
    @AppStorage("readingPositions") private var readingPositionsData: Data = Data()

    private var appTheme:  AppTheme  { AppTheme(rawValue: appThemeRaw) ?? .system }
    private var pageTheme: PageTheme { PageTheme(rawValue: pageThemeRaw) ?? .original }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if selectionState.documentURL != nil {
                    readerLayout
                } else {
                    EmptyStateView(onOpenPDF: openPDF)
                        .onDrop(of: [.pdf], isTargeted: $isDropTargeted, perform: handleDrop)
                        .overlay { if isDropTargeted { dropOverlay } }
                }
            }
            .animation(DS.Animation.standard, value: showSidebar)
            .animation(DS.Animation.standard, value: showInspector)
            .toolbar { toolbarContent }
            .navigationTitle(windowTitle)
            .onExitCommand { closeFindBar() }
        }
        .environment(ankiPrefs)
        .frame(minWidth: DS.Layout.windowMin.width, minHeight: DS.Layout.windowMin.height)
        .preferredColorScheme(appTheme.colorScheme)
        .onDrop(
            of: [.pdf],
            isTargeted: selectionState.documentURL != nil ? $isDropTargeted : nil,
            perform: handleDrop
        )
        .onReceive(NotificationCenter.default.publisher(for: .openPDFCommand)) { _ in openPDF() }
        .onReceive(NotificationCenter.default.publisher(for: .inspectorRunLastModule)) { _ in
            if !showInspector { showInspector = true }
        }
        .onChange(of: selectionState.documentURL) { _, newURL in
            if let filename = newURL?.lastPathComponent {
                sessionStore.startSession(for: filename)
            } else {
                sessionStore.endActiveSession()
            }
        }
        .onDisappear {
            sessionStore.endActiveSession()
        }
    }

    // MARK: - Reader Layout (3-panel)

    private var readerLayout: some View {
        GeometryReader { proxy in
            let totalWidth       = proxy.size.width
            let sidebarOccupied  = showSidebar   ? sidebarWidth   + 7 : 0
            let inspectorOccupied = showInspector ? inspectorWidth + 7 : 0
            let sidebarMax  = max(DS.Layout.sidebarMin,   totalWidth - inspectorOccupied - DS.Layout.pdfMin)
            let inspectorMax = max(DS.Layout.inspectorMin, totalWidth - sidebarOccupied   - DS.Layout.pdfMin)

            HStack(spacing: 0) {
                // ── Sidebar ──────────────────────────────────────────────────
                if showSidebar {
                    SidebarView(
                        pdfViewManager:      pdfViewManager,
                        savedWordsStore:     savedWordsStore,
                        bookmarkStore:       bookmarkStore,
                        sessionStore:        sessionStore,
                        currentDocumentName: selectionState.documentURL?.deletingPathExtension().lastPathComponent
                    )
                    .frame(width: sidebarWidth)

                    PanelDivider(
                        panelWidth: $sidebarWidth,
                        minWidth: DS.Layout.sidebarMin,
                        maxWidth: sidebarMax,
                        panelOnLeadingSide: true,
                        defaultWidth: DS.Layout.sidebarDefault
                    )
                }

                // ── PDF Viewer ────────────────────────────────────────────────
                VStack(spacing: DS.Spacing.sm) {
                    if searchManager.isFindBarVisible {
                        FindBarView(searchManager: searchManager, onClose: closeFindBar)
                        .transition(.opacity.combined(with: .move(edge: .top)))
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
                        pageTheme: pageTheme
                    )
                    .onReceive(NotificationCenter.default.publisher(for: .PDFViewPageChanged)) { notification in
                        guard let pdfView = notification.object as? PDFView,
                              let page    = pdfView.currentPage,
                              let index   = pdfView.document?.index(for: page),
                              let filename = selectionState.documentURL?.deletingPathExtension().lastPathComponent
                        else { return }
                        persistPage(index, for: filename)
                    }
                    .onChange(of: selectionState.documentURL) { _, newURL in
                        guard let newURL else { return }
                        restorePage(for: newURL.deletingPathExtension().lastPathComponent)
                    }
                }
                .padding(.top, DS.Spacing.sm)
                .padding(.horizontal, DS.Spacing.sm)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: pageTheme.backgroundColor))

                // ── Inspector ─────────────────────────────────────────────────
                if showInspector {
                    PanelDivider(
                        panelWidth: $inspectorWidth,
                        minWidth: DS.Layout.inspectorMin,
                        maxWidth: inspectorMax,
                        panelOnLeadingSide: false,
                        defaultWidth: DS.Layout.inspectorDefault
                    )
                    InspectorView(
                        selectedText: selectionState.selectedText,
                        contextSentence: selectionState.contextSentence,
                        pdfFilename: selectionState.documentURL?.deletingPathExtension().lastPathComponent,
                        pageNumber: currentPageNumber,
                        savedWordsStore: savedWordsStore
                    )
                    .frame(width: inspectorWidth)
                }
            }
        }
    }

    private var currentPageNumber: Int? {
        guard let pdfView = pdfViewManager.pdfView,
              let page    = pdfView.currentPage,
              let idx     = pdfView.document?.index(for: page)
        else { return nil }
        return idx + 1
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { toggleSidebar() } label: {
                Label("Toggle Sidebar", systemImage: "sidebar.left")
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
            .help("Toggle Sidebar (⌘⌥S)")
        }

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
            .keyboardShortcut("o", modifiers: [.command])
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
            Button { toggleInspector() } label: {
                Label("Toggle Inspector", systemImage: "sidebar.right")
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .help("Toggle Inspector (⌘⌥I)")
        }

        ToolbarItem(placement: .automatic) {
            Button { focusInspectorAndRun() } label: { EmptyView() }
                .keyboardShortcut("l", modifiers: [.command])
                .help("Focus Inspector & Run Last Module (⌘L)")
                .frame(width: 0, height: 0)
                .disabled(selectionState.selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
        selectionState.documentURL = url
        closeFindBar()
    }

    private func openFindBar() {
        searchManager.showFindBar()
    }

    private func closeFindBar() {
        searchManager.closeFindBar()
    }

    private func toggleSidebar()   { showSidebar.toggle() }
    private func toggleInspector() { showInspector.toggle() }

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
        if !showInspector { showInspector = true }
        NotificationCenter.default.post(name: .inspectorRunLastModule, object: nil)
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
                    selectionState.documentURL = url
                    closeFindBar()
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
