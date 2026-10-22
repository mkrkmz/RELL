//
//  SavedWordsStore+Review.swift
//  Reader for Language Learner
//
//  Review state, statistics and scheduling. Split out of
//  SavedWordsStore.swift (v20 S0), unchanged.
//

import Foundation

extension SavedWordsStore {

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


    /// When `word` would come back after `rating` — the study room's rating
    /// buttons say it before you press (v15 S2). Nothing is written.
    func nextReviewDate(for word: SavedWord, after rating: ReviewRating, at date: Date = Date()) -> Date? {
        let stored = words.first(where: { $0.id == word.id }) ?? word
        return Self.reviewed(stored, rating: rating, at: date).nextReviewAt
    }

    /// `previous` after a review graded `rating` at `reviewedAt`: tallies,
    /// history, FSRS state, next date and mastery. Pure, so a preview and the
    /// real review can't disagree.
    static func reviewed(_ previous: SavedWord, rating: ReviewRating, at reviewedAt: Date) -> SavedWord {
        let previousReviewDate = previous.lastReviewedAt

        var updated = previous
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

        if rating == .again {
            updated.incorrectCount += 1
        }

        // Legacy ease is still maintained so an older build can read the file
        // and so the FSRS seed stays meaningful — but it no longer schedules.
        switch rating {
        case .again: updated.easeFactor = max(1.3, updated.easeFactor - 0.2)
        case .hard:  updated.easeFactor = max(1.3, updated.easeFactor - 0.05)
        case .good:  break
        case .easy:  updated.easeFactor = min(3.5, updated.easeFactor + 0.15)
        }

        // ── FSRS scheduling ──────────────────────────────────────────────
        let elapsedDays = previousReviewDate.map {
            max(0, reviewedAt.timeIntervalSince($0) / 86_400)
        } ?? 0

        let priorState = previous.fsrsState ?? FSRSScheduler.seedState(
            easeFactor: previous.easeFactor,
            previousIntervalDays: Self.previousIntervalDays(for: previous),
            isMastered: previous.masteryLevel == .mastered,
            hasBeenReviewed: previous.hasBeenReviewed
        )

        // A word's very first graded review starts a fresh memory state;
        // anything else evolves the state it already had.
        let newState: FSRSState = previous.hasBeenReviewed
            ? FSRSScheduler.nextState(priorState, grade: rating.fsrsGrade, elapsedDays: elapsedDays)
            : FSRSScheduler.initialState(grade: rating.fsrsGrade)

        updated.stability = newState.stability
        updated.difficulty = newState.difficulty

        if rating == .again {
            // Relearning step: bring it back within the session rather than
            // waiting out the (sub-day) interval a lapse implies.
            updated.nextReviewAt = Calendar.current.date(byAdding: .minute, value: 10, to: reviewedAt) ?? reviewedAt
        } else {
            let days = max(1, Int(FSRSScheduler.interval(stability: newState.stability).rounded()))
            updated.nextReviewAt = Calendar.current.date(byAdding: .day, value: days, to: reviewedAt) ?? reviewedAt
        }

        // Mastery is now a read-out of memory strength rather than a counter:
        // a lapse always drops back to learning, and durable stability earns
        // "mastered". `new` stays reserved for never-reviewed words.
        if rating == .again {
            updated.masteryLevel = .learning
        } else if newState.stability >= FSRSScheduler.masteredStabilityThreshold {
            updated.masteryLevel = .mastered
        } else {
            updated.masteryLevel = .learning
        }

        return updated
    }

    /// The interval the previous engine had settled on for this word, in days —
    /// used to seed FSRS stability so a migrated library keeps its momentum.
    private static func previousIntervalDays(for word: SavedWord) -> Double? {
        guard let next = word.nextReviewAt, let last = word.lastReviewedAt else { return nil }
        let days = next.timeIntervalSince(last) / 86_400
        return days > 0 ? days : nil
    }

    func reviewEventDates() -> [Date] {
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
}
