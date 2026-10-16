//
//  ReadingSurfaceTests.swift
//  Reader for Language LearnerTests
//
//  v18 Sprint 4 — the reading screen's floating pieces: where the selection
//  bar goes (never on the selected lines while either side has room), the
//  appearance panel's three line spacings, and the hover balloon's source
//  and "saved" mark.
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class ReadingSurfaceTests: XCTestCase {

    // MARK: Selection bar placement (top-left space, y grows down)

    private func top(_ selection: ClosedRange<CGFloat>, bar: CGFloat = 32, visible: ClosedRange<CGFloat> = 0...600) -> CGFloat {
        SelectionBarPlacement.originY(selectionTop: selection.lowerBound, selectionBottom: selection.upperBound,
                                      barHeight: bar, visibleTop: visible.lowerBound, visibleBottom: visible.upperBound)
    }

    func testTheBarSitsAboveTheSelectionWhenThereIsRoom() {
        XCTAssertEqual(top(200...220), 200 - SelectionBarPlacement.gap - 32)
    }

    func testTheBarGoesBelowWhenThereIsNoRoomAbove() {
        XCTAssertEqual(top(20...40), 40 + SelectionBarPlacement.gap)
    }

    func testTheBarNeverCoversTheSelectionWhileEitherSideHasRoom() {
        for start in stride(from: CGFloat(0), through: 560, by: 7) {
            let selection = start...(start + 24)
            let y = top(selection)
            let bar = y...(y + 32)
            XCTAssertFalse(bar.overlaps(selection), "selection at \(start)")
            XCTAssertGreaterThanOrEqual(y, SelectionBarPlacement.margin, "selection at \(start)")
            XCTAssertLessThanOrEqual(y + 32, 600 - SelectionBarPlacement.margin, "selection at \(start)")
        }
    }

    func testASelectionTallerThanTheViewKeepsTheBarAtTheTop() {
        XCTAssertEqual(top(10...590), SelectionBarPlacement.margin)
    }

    func testTheBarStaysInsideTheViewSideways() {
        XCTAssertEqual(SelectionBarPlacement.originX(selectionMidX: 300, barWidth: 200, visibleLeft: 0, visibleRight: 800), 200)
        XCTAssertEqual(SelectionBarPlacement.originX(selectionMidX: 10, barWidth: 200, visibleLeft: 0, visibleRight: 800),
                       SelectionBarPlacement.margin)
        XCTAssertEqual(SelectionBarPlacement.originX(selectionMidX: 790, barWidth: 200, visibleLeft: 0, visibleRight: 800),
                       800 - 200 - SelectionBarPlacement.margin)
    }

    // MARK: Hover balloon placement (1.48 live pass: it now lives in the page)

    func testTheBalloonSitsRightBelowTheWord() {
        let y = HoverBalloonPlacement.originY(wordTop: 200, wordBottom: 220, height: 100, visibleTop: 0, visibleBottom: 600)
        XCTAssertEqual(y, 220 + HoverBalloonPlacement.gap, "touching the word, not hundreds of points away")
    }

    func testTheBalloonGoesAboveAWordAtTheBottomOfThePage() {
        let y = HoverBalloonPlacement.originY(wordTop: 560, wordBottom: 580, height: 100, visibleTop: 0, visibleBottom: 600)
        XCTAssertEqual(y, 560 - HoverBalloonPlacement.gap - 100)
    }

    func testTheBalloonNeverCoversTheWordWhileEitherSideHasRoom() {
        for top in stride(from: CGFloat(0), through: 580, by: 9) {
            let word = top...(top + 20)
            let y = HoverBalloonPlacement.originY(wordTop: word.lowerBound, wordBottom: word.upperBound, height: 120,
                                                  visibleTop: 0, visibleBottom: 600)
            XCTAssertFalse((y...(y + 120)).overlaps(word), "word at \(top)")
            let gapBelow = y - word.upperBound
            let gapAbove = word.lowerBound - (y + 120)
            XCTAssertTrue(gapBelow == HoverBalloonPlacement.gap || gapAbove == HoverBalloonPlacement.gap,
                          "right next to the word at \(top)")
        }
    }

    // MARK: Line spacing presets

    func testLineSpacingPresetsAndTheNearestToAnOlderValue() {
        XCTAssertEqual(EPUBLineSpacing.allCases.map(\.lineHeight), [1.4, 1.6, 1.9])
        XCTAssertEqual(EPUBLineSpacing.nearest(to: 1.6), .normal, "the default")
        XCTAssertEqual(EPUBLineSpacing.nearest(to: 1.2), .compact)
        XCTAssertEqual(EPUBLineSpacing.nearest(to: 1.45), .compact)
        XCTAssertEqual(EPUBLineSpacing.nearest(to: 1.7), .normal)
        XCTAssertEqual(EPUBLineSpacing.nearest(to: 1.8), .roomy)
        XCTAssertEqual(EPUBLineSpacing.nearest(to: 2.0), .roomy)
    }

    // MARK: Hover balloon

    func testTheBalloonShowsTheSourceAndForgetsItForANewWord() {
        let model = HoverLookupModel()
        XCTAssertTrue(model.begin(term: "quay", isSaved: true, cached: HoverAnswer(text: "a platform", source: .dictionary)))
        XCTAssertEqual(model.phase, .loaded("a platform"))
        XCTAssertEqual(model.source, .dictionary)
        XCTAssertTrue(model.isSaved)

        XCTAssertFalse(model.begin(term: "moorings", isSaved: false, cached: nil), "nothing cached: look it up")
        XCTAssertEqual(model.phase, .loading)
        XCTAssertNil(model.source, "the last word's source doesn't linger")
        XCTAssertFalse(model.isSaved)

        model.show(HoverAnswer(text: "ropes that hold a boat", source: .model("Apple · this Mac")))
        XCTAssertEqual(model.source?.label, "Apple · this Mac")
        model.fail()
        XCTAssertEqual(model.phase, .failed)
        XCTAssertNil(model.source)
    }

    func testASavedWordsMeaningComesFromTheNotebook() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rell-surface-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let store = SavedWordsStore(fileURL: url)
        store.add(SavedWord(term: "Quay", llmOutputs: [
            ModuleType.definitionEN.rawValue: "a platform beside water",
            ModuleType.meaningTR.rawValue: "rıhtım",
        ]))

        let answer = QuickLookupService().cachedHoverAnswer(for: "quay", savedWordsStore: store)
        XCTAssertEqual(answer?.source, .notebook, "whichever language the balloon answers in")
        XCTAssertNotNil(store.lemmaMatchedWord(for: "quay"), "the balloon marks it saved")
    }
}
