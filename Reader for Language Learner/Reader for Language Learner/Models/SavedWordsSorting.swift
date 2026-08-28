//
//  SavedWordsSorting.swift
//  Reader for Language Learner
//
//  How the saved-words list is ordered and narrowed. Split out of
//  `SavedWordsListView` (v10 Sprint 4, T3) — these are persisted
//  preferences, not view internals: the raw values back @AppStorage.
//

import SwiftUI

enum SavedWordsSortOrder: String, CaseIterable, Identifiable {
    case dateDesc = "Newest"
    case dateAsc  = "Oldest"
    case alphaAsc = "A → Z"
    case alphaDesc = "Z → A"
    var id: String { rawValue }

    /// Raw values back `@AppStorage("savedWordsSortOrder")` — keep them
    /// stable and English; the picker displays this instead.
    var localizedTitle: String {
        switch self {
        case .dateDesc:  return String(localized: "Newest")
        case .dateAsc:   return String(localized: "Oldest")
        case .alphaAsc:  return String(localized: "A → Z")
        case .alphaDesc: return String(localized: "Z → A")
        }
    }
}

enum SavedWordsFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case needsReview = "Needs Review"
    case new = "New"
    case mastered = "Mastered"
    case thisPDF = "This Document"

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .all:         return String(localized: "All")
        case .needsReview: return String(localized: "Needs Review")
        case .new:         return String(localized: "New")
        case .mastered:    return String(localized: "Mastered")
        case .thisPDF:     return String(localized: "This Document")
        }
    }
}
