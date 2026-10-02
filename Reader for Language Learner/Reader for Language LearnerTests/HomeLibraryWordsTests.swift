//
//  HomeLibraryWordsTests.swift
//  Reader for Language LearnerTests
//
//  v14 Sprint 3 — What's New shows once per version to people updating;
//  articles and stories land on their own shelves; the words list's row
//  shows the latest encounter and a one-line meaning; its filter bar fits
//  the narrowest sidebar.
//

import SwiftUI
import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class HomeLibraryWordsTests: XCTestCase {

    // MARK: What's New

    func testWhatsNewShowsOncePerVersionAfterOnboarding() async throws {
        let version = try XCTUnwrap(WhatsNew.releases.first).version
        let app = version + ".0"
        XCTAssertTrue(WhatsNew.shouldShow(appVersion: app, lastSeen: nil, hasCompletedOnboarding: true))
        XCTAssertTrue(WhatsNew.shouldShow(appVersion: app, lastSeen: "1.0", hasCompletedOnboarding: true))
        XCTAssertFalse(WhatsNew.shouldShow(appVersion: app, lastSeen: version, hasCompletedOnboarding: true),
                       "already seen")
        XCTAssertFalse(WhatsNew.shouldShow(appVersion: app, lastSeen: nil, hasCompletedOnboarding: false),
                       "a first launch gets the onboarding instead")
        XCTAssertFalse(WhatsNew.shouldShow(appVersion: "1.0", lastSeen: nil, hasCompletedOnboarding: true),
                       "no page written for this version")
    }

    func testPatchReleasesShowTheirMinorsPage() async throws {
        let version = try XCTUnwrap(WhatsNew.releases.first).version
        XCTAssertEqual(WhatsNew.minorVersion(of: "1.43.2"), "1.43")
        XCTAssertEqual(WhatsNew.page(forAppVersion: version + ".3")?.version, version)
        XCTAssertFalse(try XCTUnwrap(WhatsNew.releases.first).items.isEmpty)
    }

    // MARK: Shelves

    func testArticlesAndStoriesHaveTheirOwnShelves() async throws {
        let base = try XCTUnwrap(FileManager.default.rellAppSupportDirectory())
        func document(_ path: URL) -> RecentDocument {
            RecentDocument(path: path.path, filename: path.deletingPathExtension().lastPathComponent)
        }
        XCTAssertEqual(document(base.appendingPathComponent("Articles/The Case for Napping.epub")).shelf, .articles)
        XCTAssertEqual(document(base.appendingPathComponent("Stories/The Lantern.epub")).shelf, .stories)
        XCTAssertEqual(document(URL(fileURLWithPath: "/Users/me/Books/Crime and Punishment.epub")).shelf, .books)
        XCTAssertEqual(document(URL(fileURLWithPath: "/Users/me/Articles/notes.pdf")).shelf, .books,
                       "only RELL's own Articles folder is the Articles shelf")
    }

    // MARK: Words list

    func testLatestEncounterPerWordIsTheNewest() async {
        let word = UUID(), other = UUID()
        func met(_ id: UUID, _ title: String, daysAgo: Double) -> WordEncounter {
            WordEncounter(wordID: id, documentPath: "/\(title).epub", documentTitle: title, location: 0, isEPUB: true,
                          sentence: "", occurrences: 1, date: Date(timeIntervalSinceNow: -daysAgo * 86_400))
        }
        let latest = WordEncounterStore.latestByWord(in: [
            met(word, "Old", daysAgo: 9), met(word, "New", daysAgo: 1), met(word, "Middle", daysAgo: 4),
            met(other, "Only", daysAgo: 2),
        ])
        XCTAssertEqual(latest[word]?.documentTitle, "New")
        XCTAssertEqual(latest[other]?.documentTitle, "Only")
        XCTAssertNil(latest[UUID()])
    }

    func testRowMeaningPrefersYourLanguageAndTakesOneLine() async {
        var word = SavedWord(term: "landlady", sentence: "", llmOutputs: [
            ModuleType.definitionEN.rawValue: "A woman who rents out rooms.\nMore detail.",
            ModuleType.meaningTR.rawValue: "\n  ev sahibesi  \nkiraya veren kadın",
        ])
        XCTAssertEqual(SavedWordRow.oneLineMeaning(of: word), "ev sahibesi")
        word.llmOutputs[ModuleType.meaningTR.rawValue] = "   "
        XCTAssertEqual(SavedWordRow.oneLineMeaning(of: word), "A woman who rents out rooms.")
        word.llmOutputs = [:]
        XCTAssertNil(SavedWordRow.oneLineMeaning(of: word))
    }

    /// The narrowest sidebar (200 pt less padding): the bar stays two short
    /// lines instead of pushing the column wider or taller.
    func testFilterBarFitsTheNarrowestSidebar() async throws {
        let store = SavedWordsStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("w.json"))
        let bar = SavedWordsFilterBar(
            store: store, availableFilters: SavedWordsFilter.allCases, shownCount: 0,
            selectedFilter: .constant(.all), sortOrder: .constant(.dateDesc),
            selectedTag: .constant("Okul"), selectedCEFR: .constant(.b1), selectedLanguage: .constant(.english)
        )
        .environment(CEFREstimator(savedWordsStore: store))
        let height = try await LayoutGuard.settledHeight(of: bar, width: 184, height: 80)
        XCTAssertLessThanOrEqual(height, 80 + 1, "the filter bar forced the window to \(height) pt")
    }
}
