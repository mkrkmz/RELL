//
//  InspectorCardTests.swift
//  Reader for Language LearnerTests
//
//  v18 Sprint 2 — what the Inspector's card shows: the reader's own list,
//  what waits in •••, reordering within a row, what fits the width, and
//  lists from older or newer versions read safely.
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class InspectorCardTests: XCTestCase {

    func testTheDefaultCardsMatchTheApprovedMockup() {
        XCTAssertEqual(InspectorCardLayout.defaults(.word),
                       [.listen, .anki, .module(.definitionEN), .module(.meaningTR), .module(.collocations), .module(.examplesEN)])
        XCTAssertEqual(InspectorCardLayout.defaults(.sentence),
                       [.listen, .copy, .module(.definitionEN), .module(.meaningTR), .grammar, .simplify, .retell])
        XCTAssertEqual(InspectorCardLayout.pinned(.word, stored: nil), InspectorCardLayout.defaults(.word))
    }

    func testIdsRoundTrip() {
        for kind in CardKind.allCases {
            for item in InspectorCardLayout.available(kind) {
                XCTAssertEqual(CardItem(id: item.id), item, item.id)
            }
        }
        XCTAssertNil(CardItem(id: "module.somethingRemoved"))
        XCTAssertNil(CardItem(id: "custom.1234"), "a module from a later version is skipped, not crashed on")
    }

    func testAStoredListDropsWhatDoesntBelong() {
        let stored = ["module.etymologyEN", "copy", "module.definitionEN", "module.definitionEN", "nonsense", "grammar"]
        XCTAssertEqual(InspectorCardLayout.pinned(.word, stored: stored), [.module(.etymologyEN), .module(.definitionEN)],
                       "copy and grammar are sentence-card items; duplicates and unknown ids go")
        XCTAssertEqual(InspectorCardLayout.pinned(.sentence, stored: ["module.etymologyEN", "copy"]), [.copy],
                       "etymology isn't offered for a sentence")
        XCTAssertEqual(InspectorCardLayout.pinned(.word, stored: []), [], "an empty card is the reader's choice")
    }

    func testEverythingIsEitherOnTheCardOrInTheMenu() {
        let pinned = InspectorCardLayout.defaults(.word)
        let unpinned = InspectorCardLayout.unpinned(.word, pinned: pinned)
        XCTAssertEqual(Set(pinned).union(unpinned), Set(InspectorCardLayout.available(.word)))
        XCTAssertTrue(Set(pinned).isDisjoint(with: unpinned))
        XCTAssertEqual(unpinned.first, .module(.pronunciationEN), "the menu keeps menu order")
    }

    func testPinAndUnpin() {
        let pinned = InspectorCardLayout.pin(.module(.etymologyEN), in: [.listen])
        XCTAssertEqual(pinned, [.listen, .module(.etymologyEN)])
        XCTAssertEqual(InspectorCardLayout.pin(.listen, in: pinned), pinned, "no duplicates")
        XCTAssertEqual(InspectorCardLayout.unpin(.listen, in: pinned), [.module(.etymologyEN)])
    }

    func testMovingStaysWithinItsRow() {
        let pinned: [CardItem] = [.listen, .module(.definitionEN), .anki, .module(.meaningTR)]
        XCTAssertEqual(InspectorCardLayout.move(.module(.meaningTR), by: -1, in: pinned),
                       [.listen, .module(.meaningTR), .anki, .module(.definitionEN)],
                       "the two modules swap; the actions between them stay put")
        XCTAssertEqual(InspectorCardLayout.move(.listen, by: -1, in: pinned), pinned, "already first in its row")
        XCTAssertEqual(InspectorCardLayout.move(.listen, by: 1, in: pinned),
                       [.anki, .module(.definitionEN), .listen, .module(.meaningTR)])
    }

    func testWhatDoesntFitWaitsInTheMenu() {
        XCTAssertEqual(InspectorCardLayout.fittingCount(widths: [60, 60, 60], available: 200, spacing: 2), 3)
        XCTAssertEqual(InspectorCardLayout.fittingCount(widths: [60, 60, 60], available: 150, spacing: 2), 2)
        XCTAssertEqual(InspectorCardLayout.fittingCount(widths: [60, 60, 60], available: 123, spacing: 2), 2, "60 + 2 + 60")
        XCTAssertEqual(InspectorCardLayout.fittingCount(widths: [60, 60, 60], available: 122, spacing: 2), 2,
                       "exactly as wide as the room fits")
        XCTAssertEqual(InspectorCardLayout.fittingCount(widths: [60, 60, 60], available: 121, spacing: 2), 1)
        XCTAssertEqual(InspectorCardLayout.fittingCount(widths: [80], available: 50, spacing: 2), 0)
        XCTAssertEqual(InspectorCardLayout.fittingCount(widths: [], available: 50, spacing: 2), 0)
    }

    func testTheReadersChoiceIsRemembered() {
        let defaults = scratchDefaults()
        let custom: [CardItem] = [.module(.pronunciationEN), .listen]
        InspectorCardLayout.save(custom, for: .word, defaults: defaults)
        XCTAssertEqual(InspectorCardLayout.load(.word, defaults: defaults), custom)
        XCTAssertEqual(InspectorCardLayout.load(.sentence, defaults: defaults), InspectorCardLayout.defaults(.sentence),
                       "each card keeps its own list")
        InspectorCardLayout.reset(.word, defaults: defaults)
        XCTAssertEqual(InspectorCardLayout.load(.word, defaults: defaults), InspectorCardLayout.defaults(.word))
    }

    func testCardNamesAreLocalisedAndTheSentenceExplainsRatherThanDefines() {
        XCTAssertEqual(CardItem.title(of: .module(.definitionEN), kind: .sentence, native: .turkish), String(localized: "Explain"))
        XCTAssertEqual(CardItem.title(of: .module(.meaningTR), kind: .word, native: .turkish), Language.turkish.nativeName)
        XCTAssertEqual(CardItem.title(of: .module(.collocations), kind: .word, native: .turkish), String(localized: "Collocations"))
        XCTAssertNotEqual(ModuleType.collocations.shortTitle, "Colloc.", "the old abbreviation, never translated")
    }
}
