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

    /// Cold-launch time — part of the v14 performance baseline.
    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            makeApp().launch()
        }
    }
}
