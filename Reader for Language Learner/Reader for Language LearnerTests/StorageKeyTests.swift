//
//  StorageKeyTests.swift
//  Reader for Language LearnerTests
//
//  Pins every UserDefaults key's string. Changing one resets that setting
//  (or loses that data — reading positions, sort orders) for every user, so
//  a rename has to fail here first and be done on purpose, with migration.
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class StorageKeyTests: XCTestCase {
    func testPersistedKeysNeverChange() async {
        let pinned: [(String, String)] = [
            (StorageKey.annotationsSegment, "annotationsSegment"),
            (StorageKey.appTheme, "appTheme"),
            (StorageKey.autoRunEnabled, "autoRunEnabled"),
            (StorageKey.bulkExportFormat, "bulkExportFormat"),
            (StorageKey.fillOnSave, "fillOnSave"),
            (StorageKey.fillUsesProvider, "fillUsesProvider"),
            (StorageKey.fillStripHiddenAtCount, "fillStripHiddenAtCount"),
            (StorageKey.fillRepairVersion, "fillRepairVersion"),
            (StorageKey.studySessionSize, "studySessionSize"),
            (StorageKey.studyNewLimit, "studyNewLimit"),
            (StorageKey.studySentenceOnFront, "studySentenceOnFront"),
            (StorageKey.studyRoomFullScreen, "studyRoomFullScreen"),
            (StorageKey.customSystemPreamble, "customSystemPreamble"),
            (StorageKey.dailyReadingGoalMinutes, "dailyReadingGoalMinutes"),
            (StorageKey.dailyReminderTime, "dailyReminderTime"),
            (StorageKey.domainPreference, "domainPreference"),
            (StorageKey.epubFontSize, "epubFontSize"),
            (StorageKey.hasCompletedOnboarding, "hasCompletedOnboarding"),
            (StorageKey.hoverDictionaryEnabled, "hoverDictionaryEnabled"),
            (StorageKey.inspectorShowMoreModules, "inspectorShowMoreModules"),
            (StorageKey.inspectorWidth, "inspectorWidth"),
            (StorageKey.karaokeEnabled, "karaokeEnabled"),
            (StorageKey.librarySortOrder, "librarySortOrder"),
            (StorageKey.menuBarExtraEnabled, "menuBarExtraEnabled"),
            (StorageKey.pageAnalysisEnabled, "pageAnalysisEnabled"),
            (StorageKey.pageTheme, "pageTheme"),
            (StorageKey.pdfDisplayMode, "pdfDisplayMode"),
            (StorageKey.quizMode, "quizMode"),
            (StorageKey.readingPositions, "readingPositions"),
            (StorageKey.savedWordsSortOrder, "savedWordsSortOrder"),
            (StorageKey.sentenceTranslationEnabled, "sentenceTranslationEnabled"),
            (StorageKey.settingsSelectedTab, "settingsSelectedTab"),
            (StorageKey.sidebarWidth, "sidebarWidth"),
            (StorageKey.speechRate, "speechRate"),
            (StorageKey.temperatureOverrides, "temperatureOverrides"),
            (StorageKey.thumbnailSize, "thumbnailSize"),
            (StorageKey.typedAutoGrade, "typedAutoGrade"),
            (StorageKey.wordsSegment, "wordsSegment"),
            (StorageKey.learnerLevel, "learnerLevel"),
            (StorageKey.readingRecapEnabled, "readingRecapEnabled"),
            (StorageKey.chapterWarmUpEnabled, "chapterWarmUpEnabled"),
            (StorageKey.interlinearGlossEnabled, "interlinearGlossEnabled"),
            (StorageKey.grammarLensExpanded, "grammarLensExpanded"),
        ]
        for (key, expected) in pinned {
            XCTAssertEqual(key, expected)
        }
        XCTAssertEqual(Set(pinned.map(\.0)).count, pinned.count, "two settings share a key")
    }

    func testFeatureKeysKeepTheirStoredNames() async {
        XCTAssertEqual(ReaderWindowModel.readingPositionsKey, "readingPositions")
        XCTAssertEqual(DailyReminderManager.timeKey, "dailyReminderTime")
    }
}
