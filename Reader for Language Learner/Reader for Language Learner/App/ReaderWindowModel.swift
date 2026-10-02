//
//  ReaderWindowModel.swift
//  Reader for Language Learner
//
//  Per-window state for the reader: the document's managers, the window
//  chrome (panels, focus, zen, sheets) and the logic that moves between
//  them. It used to be ~25 `@State` properties inside ContentView, where
//  none of it could be tested and the file couldn't be split (private
//  `@State` can't be reached from an extension in another file).
//
//  Transitions here are plain state changes; ContentView wraps them in
//  `withAnimation`, which is a view concern.
//

import AppKit
import PDFKit
import SwiftUI

@MainActor
@Observable
final class ReaderWindowModel {

    // MARK: Managers (one set per window)

    let selectionState = SelectionState()
    let searchManager = PDFSearchManager()
    let pdfViewManager = PDFViewManager()
    let epubManager = EPUBViewManager()
    let toastCenter = ToastCenter()
    let epubSearchManager = EPUBSearchManager()
    let circuitBreaker = CircuitBreaker()
    let llmHealth = LLMHealthMonitor()
    let pageAnalysisService = PageAnalysisService()
    /// Coverage of the passage on screen (L3).
    let lexicalProfileService = LexicalProfileService()
    /// Whole-book coverage, computed on open when the stored one is stale (L-V2).
    let bookCoverageService = BookCoverageService()

    // MARK: Chrome

    /// Column widths are managed (and persisted) by NavigationSplitView /
    /// .inspector themselves; only visibility is app state.
    var columnVisibility: NavigationSplitViewVisibility = .all
    var showInspector = true
    var isDropTargeted = false
    var showWorkspaceReview = false
    var showStats = false
    /// The chapter warm-up popover (v13 Sprint 2).
    var showWarmUp = false
    /// The What's New page on screen, if any (v14 S3).
    var whatsNewPage: WhatsNew?
    /// The passage being rewritten at the reader's level (v13 Sprint 3).
    var gradedRewriteSource: String?
    /// File ▸ Import Web Article… sheet (v13 Sprint 4).
    var showArticleImport = false
    /// The passage being retold (v13 Sprint 4).
    var retellSource: String?
    /// "A story from your words" sheet (v13 Sprint 4).
    var showWordStory = false
    /// ⌘K (v13 Sprint 5).
    var showCommandPalette = false
    var showReadingAppearance = false

    /// Focus mode hides the side panels and remembers what was visible.
    private(set) var focusMode = false
    private var preFocusSidebar = true
    private var preFocusInspector = true

    /// Zen mode goes further than focus: full-screen, with the window toolbar
    /// and context strip hidden too (revealed on hover).
    private(set) var zenMode = false
    private var preZenSidebar = true
    private var preZenInspector = true

    /// Sentence the user dismissed; suppresses the strip until the selection changes.
    var dismissedTranslationSentence = ""

    /// This window — for tab preference and key-window session tracking.
    weak var hostWindow: NSWindow?

    var showSidebar: Bool { columnVisibility != .detailOnly }

    /// The in-reader chrome (context strip, translation strip) hides in both
    /// focus and zen modes.
    var chromeHidden: Bool { focusMode || zenMode }

    var isEPUBDocument: Bool {
        selectionState.documentURL?.pathExtension.lowercased() == "epub"
    }

    // MARK: Panels, focus, zen

    func toggleSidebar() {
        columnVisibility = showSidebar ? .detailOnly : .all
    }

    func toggleInspector() {
        showInspector.toggle()
    }

    /// Enters focus mode by hiding both side panels, remembering their prior
    /// state so exiting restores exactly what was visible.
    func toggleFocusMode() {
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

    /// Flips zen mode and returns whether the window should now be
    /// full-screen. Remembers the panel layout so exiting restores it.
    @discardableResult
    func toggleZenMode() -> Bool {
        let entering = !zenMode
        if entering {
            preZenSidebar = showSidebar
            preZenInspector = showInspector
            zenMode = true
            focusMode = false
            columnVisibility = .detailOnly
            showInspector = false
        } else {
            restoreFromZen()
        }
        return entering
    }

    /// The user left full-screen another way (green button, ⌃⌘F): drop the
    /// zen chrome without toggling the window again.
    func exitZenChrome() {
        guard zenMode else { return }
        restoreFromZen()
    }

    private func restoreFromZen() {
        zenMode = false
        columnVisibility = preZenSidebar ? .all : .detailOnly
        showInspector = preZenInspector
    }

    func setWindowFullScreen(_ full: Bool) {
        guard let window = hostWindow ?? NSApp.keyWindow ?? NSApp.mainWindow else { return }
        if window.styleMask.contains(.fullScreen) != full {
            window.toggleFullScreen(nil)
        }
    }

    /// Guarantees the Inspector receives a run notification even when it is
    /// hidden: unhide it first, then re-post on the next runloop turn so the
    /// freshly mounted view's `onReceive` is already subscribed. Re-entry is
    /// safe — once the panel is visible this only posts when `forcePost` is set.
    func revealInspectorThenPost(_ name: Notification.Name, object: Any?, forcePost: Bool = false) {
        if !showInspector {
            showInspector = true
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: name, object: object)
            }
        } else if forcePost {
            NotificationCenter.default.post(name: name, object: object)
        }
    }

    // MARK: Find

    func openFindBar() {
        if isEPUBDocument {
            epubSearchManager.showFindBar()
        } else {
            searchManager.showFindBar()
        }
    }

    func closeFindBar() {
        searchManager.closeFindBar()
        epubSearchManager.closeFindBar()
    }

    /// "Find Next" — jumps to the next match of whatever query is already
    /// in the find bar. A no-op if nothing has been searched yet.
    func findNext() {
        if isEPUBDocument {
            epubManager.findInPage(epubSearchManager.query, forward: true)
        } else {
            searchManager.next()
        }
    }

    func findPrevious() {
        if isEPUBDocument {
            epubManager.findInPage(epubSearchManager.query, forward: false)
        } else {
            searchManager.previous()
        }
    }

    // MARK: Reading positions (PDF)

    /// `@AppStorage(StorageKey.readingPositions)` in earlier versions — same key and
    /// format (JSON `[filename: pageIndex]`), so saved positions carry over.
    static let readingPositionsKey = StorageKey.readingPositions

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func savedPageIndex(for filename: String) -> Int? {
        decodedPositions()[filename]
    }

    func persistPage(_ index: Int, for filename: String) {
        Self.persistPage(index, for: filename, defaults: defaults)
    }

    /// Static so a caller with no window — the word page jumping to where a
    /// word was met — can set where a document opens.
    static func persistPage(_ index: Int, for filename: String, defaults: UserDefaults = .standard) {
        var positions = decodedPositions(defaults)
        positions[filename] = index
        defaults.set((try? JSONEncoder().encode(positions)) ?? Data(), forKey: readingPositionsKey)
    }

    private func decodedPositions() -> [String: Int] {
        Self.decodedPositions(defaults)
    }

    private static func decodedPositions(_ defaults: UserDefaults) -> [String: Int] {
        guard let data = defaults.data(forKey: readingPositionsKey) else { return [:] }
        return (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
    }

    /// A window adopting its very first document (via `.onAppear` or the
    /// `documentURL` binding changing from outside) never sees
    /// `PDFKitView`'s own `.onChange(of: selectionState.documentURL)` fire —
    /// that view doesn't exist in the hierarchy yet at the moment the URL
    /// first lands, and SwiftUI never fires `.onChange` retroactively for
    /// the state change that caused a view to mount. This covers that gap;
    /// the PDFKitView-scoped `.onChange` still handles same-window switches
    /// to a different PDF once the reader is already showing.
    func restorePageIfPDF(_ url: URL?) {
        guard let url, url.pathExtension.lowercased() != "epub" else { return }
        restorePage(for: url.deletingPathExtension().lastPathComponent)
    }

    /// Restores the saved page for a newly-opened document. Event-driven
    /// when possible: `PDFKitView.Coordinator.requestDocumentUpdate` assigns
    /// `pdfView.document` asynchronously, and PDFKit posts
    /// `.PDFViewDocumentChanged` the moment that assignment lands, so we
    /// restore right on that signal. A 0.5 s timeout still runs as a
    /// fallback, both because the notification could in principle be
    /// unreliable and because `pdfViewManager.pdfView` itself can still be
    /// nil here (a brand-new window's `PDFKitView.makeNSView` hasn't
    /// necessarily run yet) — bailing out early in that case is what once
    /// silently broke restore on first open.
    func restorePage(for filename: String) {
        guard let index = savedPageIndex(for: filename) else { return }
        let manager = pdfViewManager
        let restore = PageRestoreAttempt { [manager] in
            guard let pdfView = manager.pdfView,
                  let doc = pdfView.document,
                  // Only restore into the document this position belongs to.
                  // The observer below can fire for another window's load, and
                  // page 14 of one book is not page 14 of another.
                  doc.documentURL?.deletingPathExtension().lastPathComponent == filename,
                  index < doc.pageCount,
                  doc.page(at: index) != nil
            else { return false }

            // Navigate on the NEXT runloop pass, never inline in the
            // document-changed notification. PDFKit's own observers — the
            // thumbnail view's collection view among them — are still catching
            // up to the new document at this point, and navigating first made
            // the thumbnail view select an index against the *previous*
            // document's item count ("indexPath (0,14) out of bounds", crash).
            DispatchQueue.main.async {
                guard let pdfView = manager.pdfView,
                      let doc = pdfView.document,
                      index < doc.pageCount,
                      let page = doc.page(at: index)
                else { return }
                pdfView.go(to: page)
            }
            return true
        }

        // Register the document-load observer unconditionally. Passing a nil
        // `object` (when this window's PDFView hasn't been created yet — the
        // first-open case) observes any PDFView's load; the attempt gates on
        // this window's PDFView *and* on the document actually being the one
        // we saved a position for.
        restore.observer = NotificationCenter.default.addObserver(
            forName: Notification.Name.PDFViewDocumentChanged,
            object: pdfViewManager.pdfView,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { restore.attempt() }
        }

        // Safety net only — the observer above is the primary path now.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.5))
            restore.finish()
            restore.attempt()
        }
    }
}

// MARK: - Page restore

/// One restore-on-open attempt: runs `tryRestore` until it succeeds once,
/// then stops listening. A class (not captured locals) so the notification
/// block can reach it from its `@Sendable` closure.
@MainActor
private final class PageRestoreAttempt {
    var observer: NSObjectProtocol?
    private var didRestore = false
    private let tryRestore: () -> Bool

    init(tryRestore: @escaping () -> Bool) {
        self.tryRestore = tryRestore
    }

    func attempt() {
        guard !didRestore, tryRestore() else { return }
        didRestore = true
        finish()
    }

    func finish() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }
}
