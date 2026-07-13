//
//  ToastCenterTests.swift
//  Reader for Language LearnerTests
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class ToastCenterTests: XCTestCase {
    // CI-only gotcha: @Observable objects created in a test body must outlive
    // the test (libmalloc double-free in the runner's post-scope checker).
    private static var retained: [ToastCenter] = []

    private func makeCenter() -> ToastCenter {
        let center = ToastCenter()
        Self.retained.append(center)
        return center
    }

    func testShowPresentsMessageWithDefaultVariant() {
        let center = makeCenter()
        XCTAssertFalse(center.isPresented)

        center.show("Word saved!")

        XCTAssertTrue(center.isPresented)
        XCTAssertEqual(center.message, "Word saved!")
        XCTAssertEqual(center.variant, .success)
    }

    func testShowReplacesPreviousToast() {
        let center = makeCenter()

        center.show("Bookmark added", variant: .info)
        center.show("Bookmark removed", variant: .warning)

        XCTAssertTrue(center.isPresented)
        XCTAssertEqual(center.message, "Bookmark removed")
        XCTAssertEqual(center.variant, .warning)
    }

    func testDismissalClearsPresentationButKeepsLastMessage() {
        let center = makeCenter()
        center.show("Word saved!")

        // The DSToast modifier writes the binding back to false on timeout.
        center.isPresented = false

        XCTAssertFalse(center.isPresented)
        XCTAssertEqual(center.message, "Word saved!")
    }
}
