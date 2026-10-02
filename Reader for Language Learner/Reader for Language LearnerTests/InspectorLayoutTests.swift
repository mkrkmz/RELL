//
//  InspectorLayoutTests.swift
//  Reader for Language LearnerTests
//
//  v14 Sprint 2 — the inspector's structure: word or sentence from the
//  selection, which modules are chips and which sit behind "More", and the
//  sentence card hearing about a translation the strip cached.
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class InspectorLayoutTests: XCTestCase {

    func testOneWordIsExplainedAsAWordAndAnythingLongerAsASentence() async {
        XCTAssertEqual(ExplainMode.automatic(for: "landlady"), .word)
        XCTAssertEqual(ExplainMode.automatic(for: "  landlady\n"), .word)
        XCTAssertEqual(ExplainMode.automatic(for: "well-known"), .word)
        XCTAssertEqual(ExplainMode.automatic(for: "in debt"), .sentence)
        XCTAssertEqual(ExplainMode.automatic(for: "He was afraid of meeting her."), .sentence)
        XCTAssertEqual(ExplainMode.automatic(for: String(repeating: "a", count: 41)), .sentence)
    }

    /// Every module is reachable — as a chip or in the menu, never both —
    /// and the menu keeps the Modules menu's (⌘5–⌘9) order.
    func testChipsAndMoreMenuCoverEveryModuleOnce() async {
        let front = ModuleType.inspectorFront
        let more = ModuleType.inspectorMore
        XCTAssertEqual(front, [.definitionEN, .meaningTR, .collocations, .examplesEN])
        XCTAssertEqual(Set(front).intersection(more), [])
        XCTAssertEqual(Set(front + more), Set(ModuleType.allCases))
        XCTAssertEqual(more, ModuleType.menuOrder.filter { !front.contains($0) })
        XCTAssertEqual(more.first, .pronunciationEN)
    }

    func testCachingATranslationTellsObservers() async throws {
        let service = QuickLookupService()
        let sentence = "The landlady found the flats in a strange state."
        let before = service.translationRevision
        XCTAssertNil(service.cachedTranslation(for: sentence))
        service.storeTranslation("Ev sahibesi daireleri tuhaf bir halde buldu.", for: sentence)
        XCTAssertEqual(service.translationRevision, before + 1)
        XCTAssertEqual(service.cachedTranslation(for: sentence), "Ev sahibesi daireleri tuhaf bir halde buldu.")
    }
}
