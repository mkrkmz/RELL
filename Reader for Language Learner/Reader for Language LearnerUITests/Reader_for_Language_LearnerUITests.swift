//
//  Reader_for_Language_LearnerUITests.swift
//  Reader for Language LearnerUITests
//
//  Created by Muhammet Korkmaz on 10.02.2026.
//
//  Every launch passes -RELLTestHost: a UI test starts the real app, and
//  without the flag it would open the user's own data — alongside their own
//  copy if it's running (v14 Sprint 0).
//

import XCTest

final class Reader_for_Language_LearnerUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-RELLTestHost"]
        return app
    }

    @MainActor
    func testLaunchShowsTheHomeScreen() throws {
        let app = makeApp()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
    }

    /// Apple's accessibility audit on the home screen, the study room, the
    /// word notebook and Settings (Roadmap v19 Sprint 5). Run on request —
    /// `TEST_RUNNER_RELL_A11Y_AUDIT=1 make ui-test` — since it opens the app.
    /// Contrast and clipped-text findings are reported but don't fail it:
    /// they depend on the theme and the window size.
    @MainActor
    func testAccessibilityAudit() throws {
        guard ProcessInfo.processInfo.environment["RELL_A11Y_AUDIT"] == "1" else {
            throw XCTSkip("Set TEST_RUNNER_RELL_A11Y_AUDIT=1 to run the accessibility audit.")
        }
        let app = makeApp()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))

        func audit(_ screen: String) throws {
            try app.performAccessibilityAudit(for: [.elementDetection, .sufficientElementDescription, .hitRegion, .action, .parentChild]) { issue in
                print("A11Y [\(screen)] \(issue.auditType): \(issue.compactDescription) — \(issue.element?.debugDescription.prefix(160) ?? "")")
                return false
            }
        }

        try audit("Home")
        app.typeKey("v", modifierFlags: [.command, .option])
        _ = app.windows["Study Room"].waitForExistence(timeout: 5)
        try audit("Study Room")
        app.typeKey("k", modifierFlags: [.command, .option])
        _ = app.windows["Word Notebook"].waitForExistence(timeout: 5)
        try audit("Word Notebook")
        app.typeKey(",", modifierFlags: .command)
        sleep(1)
        try audit("Settings")
    }

    /// Cold-launch time — part of the v14 performance baseline.
    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            makeApp().launch()
        }
    }
}
