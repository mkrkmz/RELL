//
//  DailyGoal.swift
//  Reader for Language Learner
//
//  The daily goal (Roadmap v19 Sprint 5, approved mockup): minutes of
//  reading and a number of reviews. The reviews are done once the target
//  is reached — or once nothing is left to review, so a day with fewer
//  cards due never asks for what isn't there. The streak counts days with
//  both parts done; days before the goal existed count the old way (some
//  reading), so nobody's streak resets.
//

import Foundation

nonisolated enum DailyGoal {

    struct Targets: Equatable, Sendable {
        var readingMinutes: Int
        /// 0: the reviews part is off.
        var reviews: Int

        static let readingChoices = [10, 15, 20, 30, 45, 60]
        static let reviewChoices = [0, 10, 20, 30, 50]
        static let defaultReviews = 20
    }

    /// One day's work.
    struct Day: Equatable, Sendable {
        var readingSeconds: Double
        var reviews: Int
        /// Cards still due; nil when not known (a day already past).
        var dueLeft: Int?
    }

    enum Status: String, Codable, Equatable, Sendable {
        case none, half, full

        func merged(with other: Status) -> Status {
            [self, other].max { $0.rank < $1.rank }!
        }

        private var rank: Int { self == .full ? 2 : self == .half ? 1 : 0 }
    }

    static func readingDone(_ day: Day, _ targets: Targets) -> Bool {
        day.readingSeconds >= Double(max(1, targets.readingMinutes) * 60)
    }

    static func reviewsDone(_ day: Day, _ targets: Targets) -> Bool {
        targets.reviews == 0 || day.reviews >= targets.reviews || day.dueLeft == 0
    }

    static func status(_ day: Day, _ targets: Targets) -> Status {
        let reading = readingDone(day, targets), reviews = reviewsDone(day, targets)
        // With the reviews part off, a day is whole on reading alone.
        if targets.reviews == 0 { return reading ? .full : .none }
        return reading && reviews ? .full : reading || (reviews && day.reviews > 0) ? .half : .none
    }

    /// Minutes of reading still to do today.
    static func readingLeft(_ day: Day, _ targets: Targets) -> Int {
        max(0, Int((Double(targets.readingMinutes * 60) - day.readingSeconds) / 60 + 0.99))
    }

    /// Reviews still to do today: up to the target, no more than are due.
    static func reviewsLeft(_ day: Day, _ targets: Targets) -> Int {
        guard !reviewsDone(day, targets) else { return 0 }
        return min(targets.reviews - day.reviews, day.dueLeft ?? .max)
    }

    /// Days in a row with the goal done, ending today — or yesterday while
    /// today is still under way. `full` holds the days logged since `start`;
    /// before it, `legacy` days (some reading) count.
    static func streak(today: Date, todayStatus: Status, start: Date, full: Set<Date>, legacy: Set<Date>,
                       calendar: Calendar = .current) -> Int {
        let startDay = calendar.startOfDay(for: start)
        func counts(_ day: Date) -> Bool {
            day < startDay ? legacy.contains(day) : full.contains(day)
        }
        var day = calendar.startOfDay(for: today)
        var streak = 0
        if todayStatus == .full {
            streak = 1
        }
        while let previous = calendar.date(byAdding: .day, value: -1, to: day) {
            day = previous
            guard counts(day) else { break }
            streak += 1
        }
        return streak
    }
}

/// What each day since the goal began came to — small, in UserDefaults.
@MainActor
enum DailyGoalLog {
    static let capacity = 400

    static func key(_ day: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func date(_ key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// The first day the goal was kept; set the first time it's asked for.
    static func start(defaults: UserDefaults = .standard, now: Date = Date()) -> Date {
        if let stored = defaults.object(forKey: StorageKey.dailyGoalStart) as? Date { return stored }
        let day = Calendar.current.startOfDay(for: now)
        defaults.set(day, forKey: StorageKey.dailyGoalStart)
        return day
    }

    static func statuses(defaults: UserDefaults = .standard) -> [String: DailyGoal.Status] {
        guard let data = defaults.data(forKey: StorageKey.dailyGoalLog) else { return [:] }
        return (try? JSONDecoder().decode([String: DailyGoal.Status].self, from: data)) ?? [:]
    }

    /// Records `status` for `day`, never lowering what the day already
    /// reached — a day done stays done when the goal is raised later.
    static func note(_ status: DailyGoal.Status, for day: Date, defaults: UserDefaults = .standard) {
        var all = statuses(defaults: defaults)
        let key = key(day)
        let merged = (all[key] ?? .none).merged(with: status)
        guard merged != all[key] else { return }
        all[key] = merged
        if all.count > capacity {
            for old in all.keys.sorted().prefix(all.count - capacity) { all[old] = nil }
        }
        if let data = try? JSONEncoder().encode(all) {
            defaults.set(data, forKey: StorageKey.dailyGoalLog)
        }
    }

    static func fullDays(defaults: UserDefaults = .standard) -> Set<Date> {
        Set(statuses(defaults: defaults).filter { $0.value == .full }.keys.compactMap { date($0) })
    }
}
