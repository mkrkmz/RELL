//
//  LayoutGuardTests.swift
//  Reader for Language LearnerTests
//
//  Roadmap v14 Sprint 0: a guard against the crash v13's live pass found
//  twice — content in an AppKit-sized column that won't shrink raises the
//  window's minimum height; in the app the window can't grow, and AppKit
//  loops on its constraints until it throws. In a free test window the same
//  pressure shows as the window growing, which is what these tests catch.
//

import AppKit
import SwiftUI
import XCTest
@testable import Reader_for_Language_Learner

/// Hosts a view in a fixed-size window and reports how tall the window
/// ended up. A view that can't fit makes the window grow past its size.
@MainActor
enum LayoutGuard {
    private static var retained: [AnyObject] = []

    static func settledHeight<V: View>(
        of view: V,
        width: CGFloat,
        height: CGFloat,
        steps: Int = 15
    ) async throws -> CGFloat {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false
        )
        window.contentView = NSHostingView(rootView: view.frame(width: width).frame(maxHeight: .infinity))
        window.orderFrontRegardless()
        retained.append(window)
        defer { window.orderOut(nil) }
        for _ in 0..<steps {
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(25))
        }
        return window.contentLayoutRect.height
    }
}

@MainActor
final class LayoutGuardTests: XCTestCase {
    private static var retained: [AnyObject] = []

    /// The real inspector, every dependency on throwaway stores, in a short
    /// column. A sentence selection shows the phrase header and the grammar
    /// lens — the part that crashed.
    func testInspectorWithASentenceFitsAShortColumn() async throws {
        try await withDefaults([StorageKey.grammarLensExpanded: true, StorageKey.autoRunEnabled: false]) {
            let sentence = String(repeating: "The landlady found the flats in a strange and quiet state. ", count: 5)
            let height = try await LayoutGuard.settledHeight(of: inspector(selecting: sentence), width: 300, height: 480)
            XCTAssertLessThanOrEqual(height, 480 + 1, "the inspector forced the window to \(height) pt")
        }
    }

    /// A single word shows the word card instead.
    func testInspectorWithAWordFitsAShortColumn() async throws {
        try await withDefaults([StorageKey.autoRunEnabled: false]) {
            let height = try await LayoutGuard.settledHeight(of: inspector(selecting: "melancholy"), width: 300, height: 420)
            XCTAssertLessThanOrEqual(height, 420 + 1, "the inspector forced the window to \(height) pt")
        }
    }

    /// v14 S2: a sentence with its translation in the card and the Tools
    /// section, in the shortest column.
    func testInspectorWithASentenceTranslationAndToolsFitsAShortColumn() async throws {
        try await withDefaults([StorageKey.grammarLensExpanded: true, StorageKey.autoRunEnabled: false]) {
            let sentence = "He was hopelessly in debt to his landlady and was afraid of meeting her on the stairs."
            let lookup = QuickLookupService()
            lookup.storeTranslation(String(repeating: "Ev sahibesine umutsuzca borçluydu ve onunla karşılaşmaktan korkuyordu. ", count: 3), for: sentence)
            let height = try await LayoutGuard.settledHeight(of: inspector(selecting: sentence, lookup: lookup), width: 300, height: 460)
            XCTAssertLessThanOrEqual(height, 460 + 1, "the inspector forced the window to \(height) pt")
        }
    }

    /// v14 S2: the inspector in the page theme's tones fits like the default.
    func testInspectorFollowingThePageThemeFitsAShortColumn() async throws {
        try await withDefaults([StorageKey.inspectorFollowsPageTheme: true, StorageKey.autoRunEnabled: false]) {
            let previous = UserDefaults.standard.string(forKey: StorageKey.pageTheme)
            UserDefaults.standard.set(PageTheme.sepia.rawValue, forKey: StorageKey.pageTheme)
            defer { UserDefaults.standard.set(previous, forKey: StorageKey.pageTheme) }
            let height = try await LayoutGuard.settledHeight(of: inspector(selecting: "melancholy"), width: 300, height: 420)
            XCTAssertLessThanOrEqual(height, 420 + 1, "the inspector forced the window to \(height) pt")
        }
    }

    func testExpandedGrammarLensFitsAShortColumn() async throws {
        try await withDefaults([StorageKey.grammarLensExpanded: true]) {
            let sentence = String(repeating: "The old cat sleeps quietly near the warm window. ", count: 6)
            let height = try await LayoutGuard.settledHeight(
                of: GrammarLensView(sentence: sentence, language: .english), width: 180, height: 220
            )
            XCTAssertLessThanOrEqual(height, 220 + 1)
        }
    }

    // MARK: - Helpers

    private func inspector(selecting text: String, lookup given: QuickLookupService? = nil) -> some View {
        let lookup = given ?? QuickLookupService()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let words = SavedWordsStore(fileURL: folder.appendingPathComponent("saved_words.json"))
        let encounters = WordEncounterStore(fileURL: folder.appendingPathComponent("word_encounters.json"))
        let anki = AnkiModulePreferences()
        Self.retained += [words, encounters, lookup, anki]
        return InspectorView(
            selectedText: text, contextSentence: text, pdfFilename: "Test", pageNumber: 1,
            savedWordsStore: words, circuitBreaker: CircuitBreaker()
        )
        .environment(words)
        .environment(encounters)
        .environment(lookup)
        .environment(anki)
    }

    private func withDefaults(_ values: [String: Bool], _ body: () async throws -> Void) async throws {
        let defaults = UserDefaults.standard
        let previous = values.keys.map { ($0, defaults.object(forKey: $0)) }
        for (key, value) in values { defaults.set(value, forKey: key) }
        defer { for (key, value) in previous { defaults.set(value, forKey: key) } }
        try await body()
    }
}
