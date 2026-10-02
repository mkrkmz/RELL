//
//  WindowLayoutTests.swift
//  Reader for Language LearnerTests
//
//  v14 Sprint 0: the whole reader window, as the app builds it, shrunk to
//  its minimum size. The user's live pass crashed RELL by dragging the
//  window to its smallest — the update-constraints loop again: the context
//  strip's horizontal scroll view renegotiating with its truncating chips,
//  under a fixed 900 pt minimum narrower than the split view's own. Before
//  the fix this test crashed the test host the same way.
//

import AppKit
import SwiftUI
import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class WindowLayoutTests: XCTestCase {
    private static var retained: [AnyObject] = []

    /// The reader's width minimum is the split view's own (sidebar + reader
    /// + inspector minimums), so the window may stop short of 900 x 600 —
    /// but it must settle there rather than loop, and not far above it.
    func testReaderWindowSettlesAtItsMinimumSize() async throws {
        // On macOS 15 (CI's runner, 15.7) the test host itself crashed here
        // — "malloc: pointer being freed was not allocated", right after
        // "Cannot use Scene methods … without SwiftUI Lifecycle": this test
        // builds the whole reader scene in a hand-made NSWindow, outside the
        // SwiftUI lifecycle. Not the update-constraints loop the test guards
        // against, and not reproducible on macOS 26, where it runs.
        guard ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
        ) else {
            throw XCTSkip("The reader scene outside the SwiftUI lifecycle crashes the test host on macOS 15")
        }
        let size = try await settledSize(documentURL: try bookURL(), shrinkTo: DS.Layout.windowMin)
        XCTAssertLessThanOrEqual(size.width, 1_000, "content forced the window to \(size)")
        XCTAssertLessThanOrEqual(size.height, DS.Layout.windowMin.height + 1, "content forced the window to \(size)")
    }

    func testHomeWindowFitsItsMinimumSize() async throws {
        let size = try await settledSize(documentURL: nil, shrinkTo: DS.Layout.windowMin)
        XCTAssertLessThanOrEqual(size.width, DS.Layout.windowMin.width + 1, "content forced the window to \(size)")
        XCTAssertLessThanOrEqual(size.height, DS.Layout.windowMin.height + 1, "content forced the window to \(size)")
    }

    // MARK: - Helpers

    /// Builds the window the way the app's WindowGroup does, opens it large,
    /// then shrinks it to `shrinkTo` and reports the content size it settles at.
    private func settledSize(documentURL: URL?, shrinkTo target: CGSize) async throws -> CGSize {
        let savedWords = SavedWordsStore()
        let lookup = QuickLookupService()
        let stores: [AnyObject] = [savedWords, lookup]
        Self.retained += stores
        let root = ContentView(documentURL: .constant(documentURL))
            .environment(savedWords)
            .environment(lookup)
            .environment(PDFBookmarkStore())
            .environment(PDFNoteStore())
            .environment(PDFHighlightStore())
            .environment(EPUBHighlightStore())
            .environment(EPUBBookmarkStore())
            .environment(EPUBNoteStore())
            .environment(ReadingSessionStore())
            .environment(WordEncounterStore())
            .environment(RecentDocumentStore())
            .environment(DocumentCoverStore())
            .environment(AnkiModulePreferences())
            .environment(CEFREstimator(savedWordsStore: savedWords))

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .resizable, .closable, .miniaturizable], backing: .buffered, defer: false
        )
        window.contentViewController = NSHostingController(rootView: root)
        window.orderFrontRegardless()
        Self.retained.append(window)
        defer { window.orderOut(nil) }

        for _ in 0..<40 {            // let the document load
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
        }
        // Shrink in steps, the way a drag does.
        let start = window.contentLayoutRect.size
        for step in 1...10 {
            let t = CGFloat(step) / 10
            window.setContentSize(CGSize(
                width: start.width + (target.width - start.width) * t,
                height: start.height + (target.height - start.height) * t
            ))
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(40))
        }
        for _ in 0..<20 {
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(25))
        }
        return window.contentLayoutRect.size
    }

    private func bookURL() throws -> URL {
        let paragraphs = (0..<40).map { _ in
            ExtractedArticle.Block(text: String(repeating: "The landlady found the flats in a strange state. ", count: 6), isHeading: false)
        }
        let data = MiniEPUB.build(
            title: "A Very Long Book Title That Keeps Going On And On For The Context Strip",
            author: nil, language: "en",
            chapters: [.init(title: "Chapter One", blocks: paragraphs), .init(title: "Chapter Two", blocks: paragraphs)]
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("A Very Long Book Title That Keeps Going On And On For The Context Strip.epub")
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
