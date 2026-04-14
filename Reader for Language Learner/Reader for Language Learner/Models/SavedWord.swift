//
//  SavedWord.swift
//  Reader for Language Learner
//
//  Created by Codex on 15.02.2026.
//

import Foundation
import SwiftUI

/// How well the user knows a saved word. Raw value is persisted as Int.
enum MasteryLevel: Int, Codable, CaseIterable {
    case new      = 0  // Just saved, not yet reviewed
    case learning = 1  // Actively studying
    case mastered = 2  // Confident with this word

    var label: String {
        switch self {
        case .new:      return "New"
        case .learning: return "Learning"
        case .mastered: return "Mastered"
        }
    }

    var icon: String {
        switch self {
        case .new:      return "sparkle"
        case .learning: return "brain"
        case .mastered: return "checkmark.seal.fill"
        }
    }

    var color: SwiftUI.Color {
        switch self {
        case .new:      return .blue
        case .learning: return .orange
        case .mastered: return .green
        }
    }

    var next: MasteryLevel {
        MasteryLevel(rawValue: rawValue + 1) ?? .mastered
    }
}

enum ReviewStatus {
    case new
    case due
    case scheduled
    case mastered

    var label: String {
        switch self {
        case .new: return "New"
        case .due: return "Due"
        case .scheduled: return "Scheduled"
        case .mastered: return "Mastered"
        }
    }

    var icon: String {
        switch self {
        case .new: return "sparkles"
        case .due: return "clock.badge.exclamationmark"
        case .scheduled: return "clock"
        case .mastered: return "checkmark.seal.fill"
        }
    }

    var color: SwiftUI.Color {
        switch self {
        case .new: return .blue
        case .due: return .orange
        case .scheduled: return .secondary
        case .mastered: return .green
        }
    }
}

/// A single word or phrase saved by the user during reading.
struct SavedWord: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var term: String
    var sentence: String
    var pdfFilename: String?
    var pageNumber: Int?
    var mode: String          // ExplainMode.rawValue
    var domain: String        // DomainPreference.rawValue
    var notes: String
    /// Snapshot of LLM outputs at save time. Key = ModuleType.rawValue.
    var llmOutputs: [String: String]
    var savedAt: Date
    var masteryLevel: MasteryLevel
    var reviewCount: Int
    var incorrectCount: Int
    var lastReviewedAt: Date?
    var nextReviewAt: Date?

    init(
        id: UUID = UUID(),
        term: String,
        sentence: String = "",
        pdfFilename: String? = nil,
        pageNumber: Int? = nil,
        mode: String = ExplainMode.word.rawValue,
        domain: String = DomainPreference.general.rawValue,
        notes: String = "",
        llmOutputs: [String: String] = [:],
        savedAt: Date = Date(),
        masteryLevel: MasteryLevel = .new,
        reviewCount: Int = 0,
        incorrectCount: Int = 0,
        lastReviewedAt: Date? = nil,
        nextReviewAt: Date? = nil
    ) {
        self.id = id
        self.term = term
        self.sentence = sentence
        self.pdfFilename = pdfFilename
        self.pageNumber = pageNumber
        self.mode = mode
        self.domain = domain
        self.notes = notes
        self.llmOutputs = llmOutputs
        self.savedAt = savedAt
        self.masteryLevel = masteryLevel
        self.reviewCount = reviewCount
        self.incorrectCount = incorrectCount
        self.lastReviewedAt = lastReviewedAt
        self.nextReviewAt = nextReviewAt
    }

    var hasBeenReviewed: Bool {
        reviewCount > 0 || lastReviewedAt != nil
    }

    func isDue(at referenceDate: Date = Date()) -> Bool {
        if let nextReviewAt {
            return nextReviewAt <= referenceDate
        }
        return masteryLevel != .mastered
    }

    var reviewStatus: ReviewStatus {
        if masteryLevel == .mastered && !isDue() {
            return .mastered
        }
        if !hasBeenReviewed {
            return .new
        }
        if isDue() {
            return .due
        }
        return .scheduled
    }
}
