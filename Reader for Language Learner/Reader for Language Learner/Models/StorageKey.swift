//
//  StorageKey.swift
//  Reader for Language Learner
//
//  Every UserDefaults key RELL reads or writes by name. These strings are
//  persistence keys: renaming one silently resets that preference for every
//  user. `StorageKeyTests` pins the values.
//
//  Keys defined next to their feature (`Language.targetLanguageKey`,
//  `LLMConfiguration.providerTypeKey`, `AppleOnDevice.enabledKey`, ...) stay
//  there; this collects the ones that were bare string literals, several
//  repeated in up to four files.
//

import Foundation

nonisolated enum StorageKey {
    static let annotationsSegment = "annotationsSegment"
    static let appTheme = "appTheme"
    static let autoRunEnabled = "autoRunEnabled"
    static let bulkExportFormat = "bulkExportFormat"
    static let chapterWarmUpEnabled = "chapterWarmUpEnabled"
    static let customSystemPreamble = "customSystemPreamble"
    static let dailyReadingGoalMinutes = "dailyReadingGoalMinutes"
    static let dailyReminderTime = "dailyReminderTime"
    static let domainPreference = "domainPreference"
    static let epubFontSize = "epubFontSize"
    /// Fill a new word's empty card fields after saving it (v15 S1). On by default.
    static let fillOnSave = "fillOnSave"
    /// "Fill Missing" may ask the configured provider too (v15 S1). On by default.
    static let fillUsesProvider = "fillUsesProvider"
    /// The words-list strip stays hidden while this many or fewer words lack
    /// a meaning (v15 S1) — it comes back when a new word adds to them.
    static let fillStripHiddenAtCount = "fillStripHiddenAtCount"
    /// The last one-time repair of earlier fills that ran (v15 S1).
    static let fillRepairVersion = "fillRepairVersion"
    /// Study room (v15 S2): words per session (0 = all waiting), new words
    /// per session, the book sentence on the card front, and whether the
    /// window was last in full screen.
    static let studySessionSize = "studySessionSize"
    static let studyNewLimit = "studyNewLimit"
    static let studySentenceOnFront = "studySentenceOnFront"
    static let studyRoomFullScreen = "studyRoomFullScreen"
    /// Paths of books whose words don't include other copies and Kindle
    /// (v16 S1, the per-book switch).
    static let bookTitleMatchingOff = "bookTitleMatchingOff"
    /// One-shot: the book the study room opens with ("Study This Book").
    static let studyRoomPresetBookPath = "studyRoomPresetBookPath"
    /// A fill run cut short by quitting: the words and fields still to do
    /// (v16 S2), resumed at the next launch.
    static let fillPendingWordIDs = "fillPendingWordIDs"
    static let fillPendingFields = "fillPendingFields"
    /// The word notebook shows a table instead of the list (v16 S2).
    static let notebookTableMode = "notebookTableMode"
    static let grammarLensExpanded = "grammarLensExpanded"
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
    /// The "major.minor" whose What's New page was last shown (v14 S3).
    static let whatsNewLastSeen = "whatsNewLastSeen"
    static let hoverDictionaryEnabled = "hoverDictionaryEnabled"
    static let interlinearGlossEnabled = "interlinearGlossEnabled"
    static let inspectorShowMoreModules = "inspectorShowMoreModules"   // unused since v14 S2 (More is a menu)
    /// The inspector takes the page theme's tones (v14 S2). Off by default.
    static let inspectorFollowsPageTheme = "inspectorFollowsPageTheme"
    static let inspectorWidth = "inspectorWidth"
    static let karaokeEnabled = "karaokeEnabled"
    static let learnerLevel = "learnerLevel"
    static let librarySortOrder = "librarySortOrder"
    /// Library as covers or as a list (v14 S3).
    static let libraryViewStyle = "libraryViewStyle"
    static let menuBarExtraEnabled = "menuBarExtraEnabled"
    static let pageAnalysisEnabled = "pageAnalysisEnabled"
    static let pageTheme = "pageTheme"
    static let pdfDisplayMode = "pdfDisplayMode"
    static let quizMode = "quizMode"
    static let readingRecapEnabled = "readingRecapEnabled"
    static let readingPositions = "readingPositions"
    static let savedWordsSortOrder = "savedWordsSortOrder"
    static let sentenceTranslationEnabled = "sentenceTranslationEnabled"
    static let settingsSelectedTab = "settingsSelectedTab"
    static let sidebarWidth = "sidebarWidth"
    static let speechRate = "speechRate"
    static let temperatureOverrides = "temperatureOverrides"
    static let thumbnailSize = "thumbnailSize"
    static let typedAutoGrade = "typedAutoGrade"
    static let wordsSegment = "wordsSegment"
}
