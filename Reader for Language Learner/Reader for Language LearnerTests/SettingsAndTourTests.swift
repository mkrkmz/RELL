//
//  SettingsAndTourTests.swift
//  Reader for Language LearnerTests
//
//  v14 Sprint 4 — Settings split into six tabs without losing anyone's
//  stored tab, and the reading-loop tour's shape.
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class SettingsAndTourTests: XCTestCase {

    /// A selection stored before the split ("general", "llm", …) still
    /// names a tab; "general" is now Reading, where most of it went.
    func testStoredSettingsTabsStillOpen() async {
        for stored in ["general", "llm", "prompts", "appearance"] {
            XCTAssertNotNil(SettingsTab(rawValue: stored), stored)
        }
        XCTAssertEqual(SettingsTab.allCases.count, 6)
        XCTAssertEqual(Set(SettingsTab.allCases.map(\.rawValue)).count, 6)
        XCTAssertNotNil(SettingsTab(rawValue: "learning"))
        XCTAssertNotNil(SettingsTab(rawValue: "data"))
    }

    func testTourHasTheFourStepsOfTheLoop() async {
        XCTAssertEqual(ReadingLoopTour.pageCount, 4)
    }

    func testReadingGoalChoicesIncludeTheDefault() async {
        XCTAssertTrue(DashboardActivityCard.goalChoices.contains(20), "the stored default must be offered")
        XCTAssertEqual(DashboardActivityCard.goalChoices, DashboardActivityCard.goalChoices.sorted())
    }
}
