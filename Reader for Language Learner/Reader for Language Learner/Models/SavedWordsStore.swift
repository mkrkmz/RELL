//
//  SavedWordsStore.swift
//  Reader for Language Learner
//

import Foundation
import os
import SwiftUI

enum ReviewRating: String, CaseIterable, Identifiable {
    case again
    case good
    case easy

    var id: String { rawValue }

    var label: String {
        switch self {
        case .again: return "Again"
        case .good: return "Good"
        case .easy: return "Easy"
        }
    }

    var icon: String {
        switch self {
        case .again: return "arrow.counterclockwise"
        case .good: return "checkmark.circle"
        case .easy: return "checkmark.seal"
        }
    }
}

/// Manages persistence and CRUD for the user's saved vocabulary.
/// Stores data as a JSON file in Application Support.
@MainActor
@Observable
final class SavedWordsStore {
    struct ReviewActivityDay: Identifiable, Equatable {
        let date: Date
        let count: Int

        var id: Date { date }
    }

    private(set) var words: [SavedWord] = []
    var saveError: String? = nil

    private let fileURL: URL

    init(fileURL customFileURL: URL? = nil) {
        if let customFileURL {
            self.fileURL = customFileURL
            self.words = Self.load(from: customFileURL)
            return
        }

        guard let appSupport = FileManager.default.rellAppSupportDirectory() else {
            // Fallback to temp directory if Application Support unavailable
            self.fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("saved_words.json")
            self.words = []
            return
        }

        self.fileURL = appSupport.appendingPathComponent("saved_words.json")
        self.words = Self.load(from: fileURL)
    }

    // MARK: - CRUD

    func add(_ word: SavedWord) {
        if words.contains(where: {
            $0.term.lowercased() == word.term.lowercased()
                && $0.pdfFilename == word.pdfFilename
                && $0.pageNumber  == word.pageNumber
                && $0.mode        == word.mode
                && $0.domain      == word.domain
        }) {
            return
        }
        words.insert(word, at: 0)
        save()
    }

    func update(_ word: SavedWord) {
        guard let index = words.firstIndex(where: { $0.id == word.id }) else { return }
        words[index] = word
        save()
    }

    func delete(_ word: SavedWord) {
        words.removeAll { $0.id == word.id }
        save()
    }

    func delete(at offsets: IndexSet) {
        words.remove(atOffsets: offsets)
        save()
    }

    func deleteAll() {
        words.removeAll()
        save()
    }

    func isSaved(term: String, pdfFilename: String?, pageNumber: Int?) -> Bool {
        words.contains {
            $0.term.lowercased() == term.lowercased()
                && $0.pdfFilename == pdfFilename
                && $0.pageNumber == pageNumber
        }
    }

    func remove(term: String, pdfFilename: String?, pageNumber: Int?) {
        words.removeAll {
            $0.term.lowercased() == term.lowercased()
                && $0.pdfFilename == pdfFilename
                && $0.pageNumber == pageNumber
        }
        save()
    }

    func setMastery(_ level: MasteryLevel, for word: SavedWord) {
        guard let index = words.firstIndex(where: { $0.id == word.id }) else { return }
        words[index].masteryLevel = level
        switch level {
        case .new:
            words[index].nextReviewAt = words[index].savedAt
        case .learning:
            words[index].nextReviewAt = words[index].nextReviewAt ?? Date()
        case .mastered:
            words[index].nextReviewAt = nil
        }
        save()
    }

    func word(withID id: UUID) -> SavedWord? {
        words.first(where: { $0.id == id })
    }

    // MARK: - Tags / Decks

    /// All distinct tags across saved words, sorted case-insensitively.
    var allTags: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for word in words {
            for tag in word.tags {
                let key = tag.lowercased()
                if seen.insert(key).inserted {
                    ordered.append(tag)
                }
            }
        }
        return ordered.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func words(withTag tag: String) -> [SavedWord] {
        words.filter { $0.hasTag(tag) }
    }

    func tagCount(_ tag: String) -> Int {
        words.reduce(0) { $0 + ($1.hasTag(tag) ? 1 : 0) }
    }

    /// Adds a tag (single token, trimmed) to a word if not already present.
    func addTag(_ rawTag: String, to wordID: UUID) {
        let tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty, let index = words.firstIndex(where: { $0.id == wordID }) else { return }
        guard !words[index].hasTag(tag) else { return }
        words[index].tags.append(tag)
        save()
    }

    func removeTag(_ tag: String, from wordID: UUID) {
        guard let index = words.firstIndex(where: { $0.id == wordID }) else { return }
        let needle = tag.lowercased()
        words[index].tags.removeAll { $0.lowercased() == needle }
        save()
    }

    func isDue(_ word: SavedWord, at referenceDate: Date = Date()) -> Bool {
        word.isDue(at: referenceDate)
    }

    var pendingReviewCount: Int {
        let now = Date()
        return words.filter { isDue($0, at: now) }.count
    }

    var reviewedTodayCount: Int {
        let dayStart = Calendar.current.startOfDay(for: Date())
        return reviewEventDates().filter { $0 >= dayStart }.count
    }

    var masteredCount: Int {
        words.filter { $0.masteryLevel == .mastered }.count
    }

    var learningCount: Int {
        words.filter { $0.masteryLevel == .learning }.count
    }

    var newCount: Int {
        words.filter { !$0.hasBeenReviewed }.count
    }

    func words(for filename: String?) -> [SavedWord] {
        guard let filename else { return [] }
        return words.filter { $0.pdfFilename == filename }
    }

    func savedCount(for filename: String?) -> Int {
        words(for: filename).count
    }

    func dueCount(for filename: String?, at referenceDate: Date = Date()) -> Int {
        words(for: filename).filter { isDue($0, at: referenceDate) }.count
    }

    func dueWords(at referenceDate: Date = Date()) -> [SavedWord] {
        words.filter { isDue($0, at: referenceDate) }
    }

    func reviewFallbackWords() -> [SavedWord] {
        words.filter { $0.masteryLevel != .mastered }
    }

    /// Words to review, optionally scoped to a deck (tag). Due/fallback logic
    /// is computed within the chosen pool so an empty deck still falls back to
    /// its own new/learning words rather than the global set.
    func reviewQueue(includeAll: Bool, tag: String? = nil, at referenceDate: Date = Date()) -> [SavedWord] {
        let pool: [SavedWord]
        if let tag, !tag.isEmpty {
            pool = words.filter { $0.hasTag(tag) }
        } else {
            pool = words
        }

        if includeAll { return pool }

        let due = pool.filter { isDue($0, at: referenceDate) }
        if !due.isEmpty { return due }
        return pool.filter { $0.masteryLevel != .mastered }
    }

    func reviewActivity(days: Int = 35, endingAt referenceDate: Date = Date()) -> [ReviewActivityDay] {
        let calendar = Calendar.current
        let endDay = calendar.startOfDay(for: referenceDate)
        let safeDays = max(days, 1)
        let countsByDay = Dictionary(grouping: reviewEventDates()) { date in
            calendar.startOfDay(for: date)
        }.mapValues(\.count)

        return (0..<safeDays).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -(safeDays - 1 - offset), to: endDay) else {
                return nil
            }
            return ReviewActivityDay(date: day, count: countsByDay[day] ?? 0)
        }
    }

    @discardableResult
    func applyReview(_ rating: ReviewRating, to word: SavedWord, reviewedAt: Date = Date()) -> SavedWord? {
        guard let index = words.firstIndex(where: { $0.id == word.id }) else { return nil }

        var updated = words[index]
        updated.reviewCount += 1
        if updated.reviewHistory.isEmpty, let lastReviewedAt = updated.lastReviewedAt {
            updated.reviewHistory = [lastReviewedAt]
        }
        updated.reviewHistory.append(reviewedAt)
        updated.lastReviewedAt = reviewedAt

        switch rating {
        case .again:
            updated.incorrectCount += 1
            if updated.masteryLevel == .mastered {
                updated.masteryLevel = .learning
            }
            updated.nextReviewAt = Calendar.current.date(byAdding: .minute, value: 10, to: reviewedAt) ?? reviewedAt
        case .good:
            switch updated.masteryLevel {
            case .new:
                updated.masteryLevel = .learning
                updated.nextReviewAt = Calendar.current.date(byAdding: .hour, value: 8, to: reviewedAt) ?? reviewedAt
            case .learning:
                if updated.reviewCount >= 3 {
                    updated.masteryLevel = .mastered
                    updated.nextReviewAt = Calendar.current.date(byAdding: .day, value: 3, to: reviewedAt) ?? reviewedAt
                } else {
                    updated.nextReviewAt = Calendar.current.date(byAdding: .day, value: 1, to: reviewedAt) ?? reviewedAt
                }
            case .mastered:
                updated.nextReviewAt = Calendar.current.date(byAdding: .day, value: 7, to: reviewedAt) ?? reviewedAt
            }
        case .easy:
            switch updated.masteryLevel {
            case .new:
                updated.masteryLevel = .learning
                updated.nextReviewAt = Calendar.current.date(byAdding: .day, value: 1, to: reviewedAt) ?? reviewedAt
            case .learning:
                updated.masteryLevel = .mastered
                updated.nextReviewAt = Calendar.current.date(byAdding: .day, value: 7, to: reviewedAt) ?? reviewedAt
            case .mastered:
                updated.nextReviewAt = Calendar.current.date(byAdding: .day, value: 14, to: reviewedAt) ?? reviewedAt
            }
        }

        words[index] = updated
        save()
        return updated
    }

    private func reviewEventDates() -> [Date] {
        words.flatMap { word in
            if !word.reviewHistory.isEmpty {
                return word.reviewHistory
            }
            if let lastReviewedAt = word.lastReviewedAt {
                return [lastReviewedAt]
            }
            return []
        }
    }

    // MARK: - Persistence

    private func save() {
        do {
            try RELLJSONStore.save(words, to: fileURL, storeName: "SavedWordsStore")
            saveError = nil
        } catch {
            saveError = error.localizedDescription
            AppLogger.persistence.error("SavedWordsStore save failed at \(self.fileURL.path, privacy: .private): \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func load(from url: URL) -> [SavedWord] {
        RELLJSONStore.load([SavedWord].self, from: url, storeName: "SavedWordsStore", defaultValue: [])
    }
}
