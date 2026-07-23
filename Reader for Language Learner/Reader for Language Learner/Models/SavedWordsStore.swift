//
//  SavedWordsStore.swift
//  Reader for Language Learner
//

import Foundation
import os
import SwiftUI

enum ReviewRating: String, CaseIterable, Codable, Hashable, Identifiable {
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

    /// One calendar week's review accuracy, plus the running ("lifetime so
    /// far") accuracy through that week — the stats panel's bars and
    /// retention trend line come from the same array.
    struct WeeklyAccuracy: Identifiable, Equatable {
        let weekStart: Date
        let correctCount: Int
        let incorrectCount: Int
        /// Running accuracy across every review from the beginning through
        /// the end of this week. `nil` before any review has ever happened.
        let cumulativeAccuracy: Double?

        var id: Date { weekStart }
        var totalCount: Int { correctCount + incorrectCount }
        /// `nil` for a week with no reviews at all — the chart should leave
        /// a gap there rather than draw a false 0%.
        var accuracy: Double? {
            totalCount > 0 ? Double(correctCount) / Double(totalCount) : nil
        }
    }

    struct LanguageWordCount: Identifiable, Equatable {
        let language: Language
        let count: Int
        var id: String { language.rawValue }
    }

    private(set) var words: [SavedWord] = []
    var saveError: String? = nil

    private let fileURL: URL

    init(fileURL customFileURL: URL? = nil) {
        if let customFileURL {
            self.fileURL = customFileURL
            self.words = Self.load(from: customFileURL)
            backfillMissingLanguage()
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
        backfillMissingLanguage()
    }

    /// One-time migration for pre-v1.24 words, which have no `language`.
    /// Filling it at load time (not read time) means a later target-language
    /// change won't silently relabel words that were already saved.
    private func backfillMissingLanguage() {
        guard words.contains(where: { $0.language == nil }) else { return }
        let target = Language.storedTarget.rawValue
        for index in words.indices where words[index].language == nil {
            words[index].language = target
        }
        save()
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
        SpotlightIndexer.index(word)
        // Interested services (CEFR estimator) hook new saves through this —
        // save call sites stay decoupled from LLM plumbing.
        NotificationCenter.default.post(name: .savedWordAdded, object: word.id)
    }

    func update(_ word: SavedWord) {
        guard let index = words.firstIndex(where: { $0.id == word.id }) else { return }
        words[index] = word
        save()
        SpotlightIndexer.index(word)
    }

    func delete(_ word: SavedWord) {
        words.removeAll { $0.id == word.id }
        save()
        SpotlightIndexer.removeWord(id: word.id)
    }

    func delete(at offsets: IndexSet) {
        let removed = offsets.map { words[$0] }
        words.remove(atOffsets: offsets)
        save()
        removed.forEach { SpotlightIndexer.removeWord(id: $0.id) }
    }

    func deleteAll() {
        let removed = words
        words.removeAll()
        save()
        removed.forEach { SpotlightIndexer.removeWord(id: $0.id) }
    }

    func isSaved(term: String, pdfFilename: String?, pageNumber: Int?) -> Bool {
        words.contains {
            $0.term.lowercased() == term.lowercased()
                && $0.pdfFilename == pdfFilename
                && $0.pageNumber == pageNumber
        }
    }

    func remove(term: String, pdfFilename: String?, pageNumber: Int?) {
        let removed = words.filter {
            $0.term.lowercased() == term.lowercased()
                && $0.pdfFilename == pdfFilename
                && $0.pageNumber == pageNumber
        }
        words.removeAll {
            $0.term.lowercased() == term.lowercased()
                && $0.pdfFilename == pdfFilename
                && $0.pageNumber == pageNumber
        }
        save()
        removed.forEach { SpotlightIndexer.removeWord(id: $0.id) }
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

    /// User-initiated CEFR assignment — always wins over auto estimates.
    func setCEFRLevel(_ level: CEFRLevel?, for word: SavedWord) {
        guard let index = words.firstIndex(where: { $0.id == word.id }) else { return }
        words[index].cefrLevel = level?.rawValue
        words[index].cefrIsAuto = false
        save()
    }

    /// Estimator-initiated CEFR assignment — only ever fills an unrated word,
    /// so a user value can never be silently overwritten.
    func setAutoCEFRLevel(_ level: CEFRLevel, forWordID id: UUID) {
        guard let index = words.firstIndex(where: { $0.id == id }) else { return }
        guard words[index].cefrLevel == nil else { return }
        words[index].cefrLevel = level.rawValue
        words[index].cefrIsAuto = true
        save()
    }

    func addTag(_ rawTag: String, to wordID: UUID) {
        let tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty, let index = words.firstIndex(where: { $0.id == wordID }) else { return }
        guard !words[index].hasTag(tag) else { return }
        words[index].tags.append(tag)
        save()
        SpotlightIndexer.index(words[index])   // tags feed the keywords
    }

    func removeTag(_ tag: String, from wordID: UUID) {
        guard let index = words.firstIndex(where: { $0.id == wordID }) else { return }
        let needle = tag.lowercased()
        words[index].tags.removeAll { $0.lowercased() == needle }
        save()
        SpotlightIndexer.index(words[index])
    }

    // MARK: - Bulk operations (one save per call)

    func addTag(_ rawTag: String, toWordsWithIDs ids: Set<UUID>) {
        let tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return }
        var changed: [SavedWord] = []
        for index in words.indices
        where ids.contains(words[index].id) && !words[index].hasTag(tag) {
            words[index].tags.append(tag)
            changed.append(words[index])
        }
        guard !changed.isEmpty else { return }
        save()
        changed.forEach { SpotlightIndexer.index($0) }
    }

    func removeTag(_ tag: String, fromWordsWithIDs ids: Set<UUID>) {
        let needle = tag.lowercased()
        var changed: [SavedWord] = []
        for index in words.indices
        where ids.contains(words[index].id) && words[index].hasTag(tag) {
            words[index].tags.removeAll { $0.lowercased() == needle }
            changed.append(words[index])
        }
        guard !changed.isEmpty else { return }
        save()
        changed.forEach { SpotlightIndexer.index($0) }
    }

    /// Manual bulk CEFR assignment — like the single-word version, always
    /// wins over an auto estimate (`cefrIsAuto` clears on every affected word).
    func setCEFR(_ level: CEFRLevel?, forWordsWithIDs ids: Set<UUID>) {
        var changed = false
        for index in words.indices where ids.contains(words[index].id) {
            words[index].cefrLevel = level?.rawValue
            words[index].cefrIsAuto = false
            changed = true
        }
        guard changed else { return }
        save()
    }

    func setMastery(_ level: MasteryLevel, forWordsWithIDs ids: Set<UUID>) {
        var changed = false
        for index in words.indices where ids.contains(words[index].id) {
            words[index].masteryLevel = level
            changed = true
        }
        guard changed else { return }
        save()
    }

    func setLanguage(_ language: Language, forWordsWithIDs ids: Set<UUID>) {
        var changed = false
        for index in words.indices where ids.contains(words[index].id) {
            words[index].language = language.rawValue
            changed = true
        }
        guard changed else { return }
        save()
    }

    func delete(ids: Set<UUID>) {
        let removed = words.filter { ids.contains($0.id) }
        guard !removed.isEmpty else { return }
        words.removeAll { ids.contains($0.id) }
        save()
        removed.forEach { SpotlightIndexer.removeWord(id: $0.id) }
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

    /// Weekly review accuracy for the last `weeks` calendar weeks (bucketed
    /// by week-start), for the stats panel's "Review Accuracy" chart — bars
    /// per week plus a cumulative retention trend line, computed in one
    /// forward pass across the already-date-sorted events.
    func weeklyReviewAccuracy(weeks: Int = 12, endingAt referenceDate: Date = Date()) -> [WeeklyAccuracy] {
        let calendar = Calendar.current
        guard let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: referenceDate)?.start else {
            return []
        }
        let safeWeeks = max(weeks, 1)
        let events = words.flatMap(\.reviewEvents).sorted { $0.date < $1.date }
        let eventsByWeek = Dictionary(grouping: events) { event in
            calendar.dateInterval(of: .weekOfYear, for: event.date)?.start ?? calendar.startOfDay(for: event.date)
        }

        var cumulativeCorrect = 0
        var cumulativeTotal = 0
        var eventIndex = events.startIndex

        return (0..<safeWeeks).compactMap { offset -> WeeklyAccuracy? in
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -(safeWeeks - 1 - offset), to: currentWeekStart),
                  let weekEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart)
            else { return nil }

            // Roll the running totals forward to include every event
            // through this week's end, in date order.
            while eventIndex < events.endIndex, events[eventIndex].date < weekEnd {
                if events[eventIndex].rating != .again { cumulativeCorrect += 1 }
                cumulativeTotal += 1
                eventIndex += 1
            }

            let weekEvents = eventsByWeek[weekStart] ?? []
            let correct = weekEvents.filter { $0.rating != .again }.count
            let incorrect = weekEvents.filter { $0.rating == .again }.count
            let cumulativeAccuracy = cumulativeTotal > 0 ? Double(cumulativeCorrect) / Double(cumulativeTotal) : nil

            return WeeklyAccuracy(
                weekStart: weekStart,
                correctCount: correct,
                incorrectCount: incorrect,
                cumulativeAccuracy: cumulativeAccuracy
            )
        }
    }

    /// All-time review accuracy across every recorded rated event. `nil`
    /// before the user has ever answered a review card.
    var lifetimeReviewAccuracy: Double? {
        let events = words.flatMap(\.reviewEvents)
        guard !events.isEmpty else { return nil }
        let correct = events.filter { $0.rating != .again }.count
        return Double(correct) / Double(events.count)
    }

    var lifetimeReviewEventCount: Int {
        words.reduce(0) { $0 + $1.reviewEvents.count }
    }

    /// Review streak (current/longest) and banked auto-freezes, derived purely
    /// from the recorded review dates — see `ReviewStreakCalculator`.
    func reviewStreak(at referenceDate: Date = Date()) -> ReviewStreak {
        ReviewStreakCalculator.compute(reviewDays: reviewEventDates(), today: referenceDate)
    }

    /// Saved-word counts grouped by target language, descending — the
    /// language-breakdown card only renders once this has ≥2 entries
    /// (nothing to break down for a single-language library). Words saved
    /// before v1.24 (`language == nil`) are excluded rather than lumped
    /// into an "unknown" bucket.
    var wordCountsByLanguage: [LanguageWordCount] {
        let grouped = Dictionary(grouping: words.compactMap { word in
            word.language.flatMap(Language.init(rawValue:))
        }, by: { $0 })
        return grouped
            .map { LanguageWordCount(language: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
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

        updated.reviewEvents.append(ReviewEvent(date: reviewedAt, rating: rating))
        if updated.reviewEvents.count > 500 {
            updated.reviewEvents.removeFirst(updated.reviewEvents.count - 500)
        }

        switch rating {
        case .again:
            updated.incorrectCount += 1
            if updated.masteryLevel == .mastered {
                updated.masteryLevel = .learning
            }
            updated.easeFactor = max(1.3, updated.easeFactor - 0.2)
            updated.nextReviewAt = Calendar.current.date(byAdding: .minute, value: 10, to: reviewedAt) ?? reviewedAt
        case .good:
            switch updated.masteryLevel {
            case .new:
                updated.masteryLevel = .learning
                updated.nextReviewAt = Calendar.current.date(byAdding: .hour, value: 8, to: reviewedAt) ?? reviewedAt
            case .learning:
                if updated.reviewCount >= 3 {
                    updated.masteryLevel = .mastered
                    updated.nextReviewAt = scheduledDate(byAdding: 3, to: reviewedAt, ease: updated.easeFactor)
                } else {
                    updated.nextReviewAt = scheduledDate(byAdding: 1, to: reviewedAt, ease: updated.easeFactor)
                }
            case .mastered:
                updated.nextReviewAt = scheduledDate(byAdding: 7, to: reviewedAt, ease: updated.easeFactor)
            }
        case .easy:
            updated.easeFactor = min(3.5, updated.easeFactor + 0.15)
            switch updated.masteryLevel {
            case .new:
                updated.masteryLevel = .learning
                updated.nextReviewAt = scheduledDate(byAdding: 1, to: reviewedAt, ease: updated.easeFactor)
            case .learning:
                updated.masteryLevel = .mastered
                updated.nextReviewAt = scheduledDate(byAdding: 7, to: reviewedAt, ease: updated.easeFactor)
            case .mastered:
                updated.nextReviewAt = scheduledDate(byAdding: 14, to: reviewedAt, ease: updated.easeFactor)
            }
        }

        words[index] = updated
        save()
        return updated
    }

    /// Scales a base day interval by the word's ease factor relative to the
    /// 2.5 neutral default, so words with the default ease keep today's
    /// fixed schedule exactly while consistently-easy/hard words drift.
    private func scheduledDate(byAdding baseDays: Int, to date: Date, ease: Double) -> Date {
        let scaledDays = max(1, Int((Double(baseDays) * ease / 2.5).rounded()))
        return Calendar.current.date(byAdding: .day, value: scaledDays, to: date) ?? date
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
