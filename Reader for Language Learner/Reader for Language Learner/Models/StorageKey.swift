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
