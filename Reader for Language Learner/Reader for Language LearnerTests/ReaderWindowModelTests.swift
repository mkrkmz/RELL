//
//  ReaderWindowModelTests.swift
//  Reader for Language LearnerTests
//
//  v1.41: the window chrome state machine (panels, focus, zen) and PDF
//  reading positions, now testable outside ContentView.
//

import SwiftUI
import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class ReaderWindowModelTests: XCTestCase {
    private static var retained: [AnyObject] = []

    private func makeModel(defaults: UserDefaults? = nil) -> ReaderWindowModel {
        let suite = defaults ?? {
            let name = "ReaderWindowModelTests-\(UUID().uuidString)"
            addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: name) }
            return UserDefaults(suiteName: name)!
        }()
        let model = ReaderWindowModel(defaults: suite)
        Self.retained.append(model)
        return model
    }

    func testFocusModeHidesPanelsAndRestoresTheLayoutItFound() async {
        let model = makeModel()
        model.columnVisibility = .detailOnly   // sidebar already hidden
        model.showInspector = true

        model.toggleFocusMode()
        XCTAssertTrue(model.focusMode)
        XCTAssertFalse(model.showSidebar)
        XCTAssertFalse(model.showInspector)
        XCTAssertTrue(model.chromeHidden)

        model.toggleFocusMode()
        XCTAssertFalse(model.focusMode)
        XCTAssertFalse(model.showSidebar, "the sidebar was hidden before, so it stays hidden")
        XCTAssertTrue(model.showInspector)
    }

    func testZenModeSupersedesFocusAndRestoresThePreFocusChoiceItSaw() async {
        let model = makeModel()
        XCTAssertTrue(model.toggleZenMode(), "entering asks for full-screen")
        XCTAssertTrue(model.zenMode)
        XCTAssertFalse(model.focusMode)
        XCTAssertFalse(model.showSidebar)
        XCTAssertFalse(model.showInspector)

        XCTAssertFalse(model.toggleZenMode(), "leaving asks to exit full-screen")
        XCTAssertFalse(model.zenMode)
        XCTAssertTrue(model.showSidebar)
        XCTAssertTrue(model.showInspector)
    }

    func testEnteringZenFromFocusClearsFocus() async {
        let model = makeModel()
        model.toggleFocusMode()
        model.toggleZenMode()
        XCTAssertTrue(model.zenMode)
        XCTAssertFalse(model.focusMode)
    }

    /// Leaving full-screen with the green button: zen chrome goes, the
    /// window isn't toggled again.
    func testExitingFullScreenElsewhereDropsZenChrome() async {
        let model = makeModel()
        model.showInspector = false
        model.toggleZenMode()
        model.exitZenChrome()
        XCTAssertFalse(model.zenMode)
        XCTAssertFalse(model.showInspector, "restored to what it was before zen")
        model.exitZenChrome()   // no-op outside zen
        XCTAssertFalse(model.zenMode)
    }

    func testToggleSidebarAndInspector() async {
        let model = makeModel()
        model.toggleSidebar()
        XCTAssertFalse(model.showSidebar)
        model.toggleSidebar()
        XCTAssertTrue(model.showSidebar)
        model.toggleInspector()
        XCTAssertFalse(model.showInspector)
    }

    func testRevealInspectorShowsItBeforePosting() async {
        let model = makeModel()
        model.showInspector = false
        model.revealInspectorThenPost(Notification.Name("ReaderWindowModelTests.none"), object: nil)
        XCTAssertTrue(model.showInspector)
    }

    // MARK: Reading positions

    func testReadingPositionsPersistPerDocument() async {
        let name = "ReaderWindowModelTests-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: name) }
        let defaults = UserDefaults(suiteName: name)!

        let first = makeModel(defaults: defaults)
        first.persistPage(13, for: "book-a")
        first.persistPage(2, for: "book-b")
        first.persistPage(14, for: "book-a")

        let second = makeModel(defaults: defaults)
        XCTAssertEqual(second.savedPageIndex(for: "book-a"), 14)
        XCTAssertEqual(second.savedPageIndex(for: "book-b"), 2)
        XCTAssertNil(second.savedPageIndex(for: "book-c"))
    }

    /// Same key and JSON shape as the old `@AppStorage("readingPositions")`,
    /// so positions saved before v1.41 still restore.
    func testReadsPositionsWrittenByEarlierVersions() async throws {
        let name = "ReaderWindowModelTests-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: name) }
        let defaults = UserDefaults(suiteName: name)!
        defaults.set(try JSONEncoder().encode(["legacy-book": 41]), forKey: "readingPositions")

        XCTAssertEqual(makeModel(defaults: defaults).savedPageIndex(for: "legacy-book"), 41)
    }

    func testEPUBDetectionFollowsTheOpenDocument() async {
        let model = makeModel()
        XCTAssertFalse(model.isEPUBDocument)
        model.selectionState.documentURL = URL(fileURLWithPath: "/tmp/Book.EPUB")
        XCTAssertTrue(model.isEPUBDocument)
        model.selectionState.documentURL = URL(fileURLWithPath: "/tmp/Paper.pdf")
        XCTAssertFalse(model.isEPUBDocument)
    }
}
