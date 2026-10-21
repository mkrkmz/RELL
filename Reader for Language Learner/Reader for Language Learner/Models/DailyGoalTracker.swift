//
//  DailyGoalTracker.swift
//  Reader for Language Learner
//
//  Today's goal, live (Roadmap v19 Sprint 5): reading time from the
//  sessions, reviews and cards still due from the saved words. Once a
//  minute — and when asked — today's status is written to the log, so the
//  streak knows the day even if the home screen is never opened, and the
//  daily reminder is told when today's goal is done.
//

import Foundation

@MainActor
@Observable
final class DailyGoalTracker {
    /// Off the main actor: on macOS 15 a main-actor deinit run outside a
    /// task crashes when it releases another one (v16 S0, CI crash reports).
    nonisolated deinit {}

    struct WeekDay: Identifiable, Equatable {
        let id: Date
        let status: DailyGoal.Status
        let isToday: Bool
    }

    @ObservationIgnored private let sessions: ReadingSessionStore
    @ObservationIgnored private let words: SavedWordsStore
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var lastReminderState: String?
    /// Bumped on every refresh: reading time grows with the clock, which
    /// nothing observable reports.
    private(set) var tick = 0

    /// The app's tracker, set at launch. Read directly rather than through
    /// the SwiftUI environment: one more environment value on the reader
    /// window cost ~200 ms of cold launch in Debug (v19 S6, measured).
    @ObservationIgnored nonisolated(unsafe) static weak var current: DailyGoalTracker?

    /// `keepsLog` false in a unit-test host: nothing is written, no reminder.
    init(sessions: ReadingSessionStore, words: SavedWordsStore, keepsLog: Bool = true) {
        self.sessions = sessions
        self.words = words
        Self.current = self
        guard keepsLog else { return }
        _ = DailyGoalLog.start()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    var targets: DailyGoal.Targets {
        let defaults = UserDefaults.standard
        return DailyGoal.Targets(
            readingMinutes: defaults.object(forKey: StorageKey.dailyReadingGoalMinutes) as? Int ?? 20,
            reviews: defaults.object(forKey: StorageKey.dailyGoalReviews) as? Int ?? DailyGoal.Targets.defaultReviews
        )
    }

    var today: DailyGoal.Day {
        _ = tick
        return DailyGoal.Day(readingSeconds: sessions.todayReadingTime, reviews: words.reviewedTodayCount,
                             dueLeft: words.pendingReviewCount)
    }

    var todayStatus: DailyGoal.Status { DailyGoal.status(today, targets) }

    var streak: Int {
        _ = tick
        let calendar = Calendar.current
        return DailyGoal.streak(
            today: Date(),
            todayStatus: todayStatus,
            start: DailyGoalLog.start(),
            full: DailyGoalLog.fullDays(),
            legacy: Set(sessions.sessions.map { calendar.startOfDay(for: $0.startedAt) })
        )
    }

    /// The last seven days, today last. A past day shows the better of what
    /// was logged and what its history adds up to.
    var week: [WeekDay] {
        _ = tick
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let logged = DailyGoalLog.statuses()
        let reviewDays = words.reviewEventDates().map { calendar.startOfDay(for: $0) }
        let targets = targets
        return (0..<7).compactMap { offset -> WeekDay? in
            guard let day = calendar.date(byAdding: .day, value: offset - 6, to: todayStart),
                  let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            if offset == 6 { return WeekDay(id: day, status: todayStatus, isToday: true) }
            let reading = sessions.sessions.filter { $0.startedAt >= day && $0.startedAt < next }
                .reduce(0.0) { $0 + $1.durationSeconds }
            let derived = DailyGoal.status(
                DailyGoal.Day(readingSeconds: reading, reviews: reviewDays.filter { $0 == day }.count, dueLeft: nil),
                targets
            )
            let status = (logged[DailyGoalLog.key(day)] ?? .none).merged(with: derived)
            return WeekDay(id: day, status: status, isToday: false)
        }
    }

    /// One line for the menu bar and the reminder: what today came to.
    var summary: String {
        let day = today, targets = targets
        let reading = String(localized: "\(min(targets.readingMinutes, Int(day.readingSeconds / 60)))/\(targets.readingMinutes) min")
        guard targets.reviews > 0 else { return reading }
        let reviews = DailyGoal.reviewsDone(day, targets)
            ? String(localized: "reviews done")
            : String(localized: "\(day.reviews)/\(targets.reviews) cards")
        return reading + " · " + reviews
    }

    /// What's left today, for the reminder; nil when the goal is done.
    var remaining: String? {
        let day = today, targets = targets
        let readingLeft = DailyGoal.readingLeft(day, targets)
        let reviewsLeft = targets.reviews > 0 ? DailyGoal.reviewsLeft(day, targets) : 0
        switch (readingLeft > 0, reviewsLeft > 0) {
        case (true, true):   return String(localized: "\(readingLeft) min of reading and \(reviewsLeft) reviews left today.")
        case (true, false):  return String(localized: "\(readingLeft) min of reading left today; reviews are done.")
        case (false, true):  return String(localized: "\(reviewsLeft) reviews left today; reading is done.")
        case (false, false): return nil
        }
    }

    func refresh() {
        tick += 1
        let status = todayStatus
        DailyGoalLog.note(status, for: Date())
        // The reminder follows the goal: rebuilt when today's state changes.
        let state = "\(DailyGoalLog.key(Date()))|\(status.rawValue)|\(remaining == nil)"
        if state != lastReminderState {
            lastReminderState = state
            DailyReminderManager.shared.goalChanged(done: status == .full, remaining: remaining)
        }
    }
}
