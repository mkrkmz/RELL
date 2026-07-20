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

    /// `label` above feeds string-interpolation contexts (accessibility
    /// labels, `.help`) where raw English is a pre-existing, lower-visibility
    /// gap; visible UI text should use this instead — see CLAUDE.md's
    /// `Text(String)` skips the catalog warning.
    var localizedTitle: String {
        switch self {
        case .new:      return String(localized: "New")
        case .learning: return String(localized: "Learning")
        case .mastered: return String(localized: "Mastered")
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
        case .new:      return DS.Color.accent
        case .learning: return DS.Color.warning
        case .mastered: return DS.Color.success
        }
    }

    var next: MasteryLevel {
        MasteryLevel(rawValue: rawValue + 1) ?? .mastered
    }
}

/// CEFR proficiency level, user-assigned per word. nil = unrated.
enum CEFRLevel: String, CaseIterable, Codable, Identifiable {
    case a1 = "A1"
    case a2 = "A2"
    case b1 = "B1"
    case b2 = "B2"
    case c1 = "C1"
    case c2 = "C2"

    var id: String { rawValue }

    /// Badge tint for the saved-word row — green (beginner) through red (advanced).
    var badgeColor: SwiftUI.Color {
        switch self {
        case .a1, .a2: return DS.Color.success
        case .b1, .b2: return DS.Color.warning
        case .c1, .c2: return DS.Color.danger
        }
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
        case .new: return DS.Color.accent
        case .due: return DS.Color.warning
        case .scheduled: return DS.Color.textSecondary
        case .mastered: return DS.Color.success
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
    /// User-assigned deck labels. Single-token, stored as entered, matched
    /// case-insensitively.
    var tags: [String]
    /// Snapshot of LLM outputs at save time. Key = ModuleType.rawValue.
    var llmOutputs: [String: String]
    var savedAt: Date
    var masteryLevel: MasteryLevel
    var reviewCount: Int
    var incorrectCount: Int
    var lastReviewedAt: Date?
    var reviewHistory: [Date]
    var nextReviewAt: Date?
    /// Per-word SRS ease multiplier (SM-2 style). 2.5 is the neutral default —
    /// `nextReviewAt` scheduling multiplies its base interval by `easeFactor / 2.5`,
    /// so untouched words keep today's fixed intervals exactly.
    var easeFactor: Double
    /// CEFRLevel.rawValue. nil = unrated.
    var cefrLevel: String?
    /// True when `cefrLevel` came from the LLM estimator rather than the
    /// user — auto values show an AI marker and manual assignment clears this.
    var cefrIsAuto: Bool
    /// Language.rawValue for the word being learned. nil on words saved
    /// before v1.24 — `SavedWordsStore` backfills those once from the
    /// target language at store-load time, not on every read, so a later
    /// target-language change doesn't silently relabel old words.
    var language: String?

    init(
        id: UUID = UUID(),
        term: String,
        sentence: String = "",
        pdfFilename: String? = nil,
        pageNumber: Int? = nil,
        mode: String = ExplainMode.word.rawValue,
        domain: String = DomainPreference.general.rawValue,
        notes: String = "",
        tags: [String] = [],
        llmOutputs: [String: String] = [:],
        savedAt: Date = Date(),
        masteryLevel: MasteryLevel = .new,
        reviewCount: Int = 0,
        incorrectCount: Int = 0,
        lastReviewedAt: Date? = nil,
        reviewHistory: [Date] = [],
        nextReviewAt: Date? = nil,
        easeFactor: Double = 2.5,
        cefrLevel: String? = nil,
        cefrIsAuto: Bool = false,
        language: String? = nil
    ) {
        self.id = id
        self.term = term
        self.sentence = sentence
        self.pdfFilename = pdfFilename
        self.pageNumber = pageNumber
        self.mode = mode
        self.domain = domain
        self.notes = notes
        self.tags = tags
        self.llmOutputs = llmOutputs
        self.savedAt = savedAt
        self.masteryLevel = masteryLevel
        self.reviewCount = reviewCount
        self.incorrectCount = incorrectCount
        self.lastReviewedAt = lastReviewedAt
        self.reviewHistory = reviewHistory
        self.nextReviewAt = nextReviewAt
        self.easeFactor = easeFactor
        self.cefrLevel = cefrLevel
        self.cefrIsAuto = cefrIsAuto
        self.language = language
    }

    /// Best available text for the back of a review card.
    /// Priority: English definition → native meaning → any output → context sentence.
    var reviewDefinition: String {
        let priority: [String] = [
            ModuleType.definitionEN.rawValue,
            ModuleType.meaningTR.rawValue,
        ]
        for key in priority {
            if let text = llmOutputs[key], !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        }
        return llmOutputs.values.first(where: { !$0.isEmpty })
            ?? (sentence.isEmpty ? "No definition saved." : sentence)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case term
        case sentence
        case pdfFilename
        case pageNumber
        case mode
        case domain
        case notes
        case tags
        case llmOutputs
        case savedAt
        case masteryLevel
        case reviewCount
        case incorrectCount
        case lastReviewedAt
        case reviewHistory
        case nextReviewAt
        case easeFactor
        case cefrLevel
        case cefrIsAuto
        case language
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        term = try container.decode(String.self, forKey: .term)
        sentence = try container.decodeIfPresent(String.self, forKey: .sentence) ?? ""
        pdfFilename = try container.decodeIfPresent(String.self, forKey: .pdfFilename)
        pageNumber = try container.decodeIfPresent(Int.self, forKey: .pageNumber)
        mode = try container.decodeIfPresent(String.self, forKey: .mode) ?? ExplainMode.word.rawValue
        domain = try container.decodeIfPresent(String.self, forKey: .domain) ?? DomainPreference.general.rawValue
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        llmOutputs = try container.decodeIfPresent([String: String].self, forKey: .llmOutputs) ?? [:]
        savedAt = try container.decodeIfPresent(Date.self, forKey: .savedAt) ?? Date()
        masteryLevel = try container.decodeIfPresent(MasteryLevel.self, forKey: .masteryLevel) ?? .new
        reviewCount = try container.decodeIfPresent(Int.self, forKey: .reviewCount) ?? 0
        incorrectCount = try container.decodeIfPresent(Int.self, forKey: .incorrectCount) ?? 0
        lastReviewedAt = try container.decodeIfPresent(Date.self, forKey: .lastReviewedAt)
        reviewHistory = try container.decodeIfPresent([Date].self, forKey: .reviewHistory) ?? []
        nextReviewAt = try container.decodeIfPresent(Date.self, forKey: .nextReviewAt)
        easeFactor = try container.decodeIfPresent(Double.self, forKey: .easeFactor) ?? 2.5
        cefrLevel = try container.decodeIfPresent(String.self, forKey: .cefrLevel)
        cefrIsAuto = try container.decodeIfPresent(Bool.self, forKey: .cefrIsAuto) ?? false
        language = try container.decodeIfPresent(String.self, forKey: .language)
    }

    var hasBeenReviewed: Bool {
        reviewCount > 0 || lastReviewedAt != nil
    }

    func hasTag(_ tag: String) -> Bool {
        let needle = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return false }
        return tags.contains { $0.lowercased() == needle }
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
