//
//  WordStatus.swift
//  Reader for Language Learner
//
//  One status language for a saved word (Roadmap v18 Sprint 5, approved
//  mockup): the notebook's rows and table, the word page, the study card
//  and the session summary all show a word's state the same way — a mark,
//  a word and a colour, so it reads without the colour too.
//

import SwiftUI

enum WordStatus: Equatable, Sendable {
    /// Its review is due.
    case waiting
    /// Never studied.
    case new
    /// Next review at this date.
    case scheduled(Date)
    /// A mastered word that isn't due.
    case settled
    /// Missed often; shown ahead of the others.
    case struggling

    static func of(_ word: SavedWord, now: Date = Date()) -> WordStatus {
        if word.isStruggling { return .struggling }
        switch word.reviewStatus {
        case .mastered: return .settled
        case .new: return .new
        case .due: return .waiting
        case .scheduled: return word.nextReviewAt.map(WordStatus.scheduled) ?? .waiting
        }
    }

    /// The mark: a symbol that tells the states apart without colour.
    var symbol: String {
        switch self {
        case .waiting: return "circle.fill"
        case .new: return "sparkle"
        case .scheduled: return "circle"
        case .settled: return "checkmark"
        case .struggling: return "arrow.counterclockwise"
        }
    }

    func title(now: Date = Date()) -> String {
        switch self {
        case .waiting: return String(localized: "Waiting")
        case .new: return String(localized: "New")
        case .scheduled(let date): return Self.relative(date, now: now)
        case .settled: return String(localized: "Settled")
        case .struggling: return String(localized: "You keep forgetting")
        }
    }

    @MainActor
    var color: SwiftUI.Color {
        switch self {
        case .waiting: return DS.Color.warning
        case .new: return DS.Color.accent
        case .scheduled: return DS.Color.textSecondary
        case .settled: return DS.Color.success
        case .struggling: return DS.Color.danger
        }
    }

    /// "in 3 days", "tomorrow" — when a scheduled word comes back.
    static func relative(_ date: Date, now: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

/// How well a word is remembered right now, in words (approved: the
/// percentage never stands on its colour alone).
nonisolated enum RecallStrength: Equatable, Sendable {
    case strong, fair, weak

    init(_ recall: Double) {
        self = recall >= 0.8 ? .strong : recall >= 0.5 ? .fair : .weak
    }

    var title: String {
        switch self {
        case .strong: return String(localized: "Strong")
        case .fair: return String(localized: "Fair")
        case .weak: return String(localized: "Weak")
        }
    }

    @MainActor
    var color: SwiftUI.Color {
        switch self {
        case .strong: return DS.Color.success
        case .fair: return DS.Color.warning
        case .weak: return DS.Color.danger
        }
    }
}

extension ReviewRating {
    /// The mark a review answer leaves: ↺ – ✓ ✓✓, the same on the rating
    /// buttons, the session's trail and the word page's history.
    var mark: String {
        switch self {
        case .again: return "↺"
        case .hard: return "–"
        case .good: return "✓"
        case .easy: return "✓✓"
        }
    }

    @MainActor
    var tint: SwiftUI.Color {
        switch self {
        case .again: return DS.Color.danger
        case .hard: return DS.Color.warning
        case .good: return DS.Color.accent
        case .easy: return DS.Color.success
        }
    }

}
