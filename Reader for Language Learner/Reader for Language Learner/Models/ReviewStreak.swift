//
//  ReviewStreak.swift
//  Reader for Language Learner
//
//  Review streak + earned auto-freeze, computed purely from the recorded
//  review-event dates — no separate persistence. `ReviewStreakCalculator`
//  replays the review days in order, banking one freeze per 7 streak-days
//  (max 2) and auto-consuming freezes to bridge single missed days, so the
//  result is a deterministic function of (review days, today).
//

import Foundation

struct ReviewStreak: Equatable {
    /// Consecutive review days ending at (or graced through) today.
    var current: Int
    /// Best run ever recorded.
    var longest: Int
    /// Freezes still banked (0…`maxFreezes`) after any auto-consumption.
    var freezesRemaining: Int
    /// The streak is alive but today has no review yet — read today to keep it.
    var isAtRiskToday: Bool

    static let empty = ReviewStreak(current: 0, longest: 0, freezesRemaining: 0, isAtRiskToday: false)

    var hasStreak: Bool { current > 0 }
}

enum ReviewStreakCalculator {
    /// Most freezes that can be banked at once.
    static let maxFreezes = 2
    /// Streak days needed to earn one freeze.
    static let daysPerFreeze = 7

    /// Deterministic streak from the recorded review dates. Freezes are earned
    /// as the run grows and spent to bridge missed days, all by replaying the
    /// days forward — the same input always yields the same streak, so no
    /// freeze ledger needs persisting.
    static func compute(
        reviewDays: [Date],
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> ReviewStreak {
        // Unique day-starts, ascending.
        let days = Set(reviewDays.map { calendar.startOfDay(for: $0) }).sorted()
        guard let firstDay = days.first else { return .empty }

        // Integer day index relative to the first review day (DST-safe).
        func index(of date: Date) -> Int {
            calendar.dateComponents([.day], from: firstDay, to: calendar.startOfDay(for: date)).day ?? 0
        }

        var current = 0
        var longest = 0
        var freezes = 0
        var covered: Int? = nil   // day-index of the last day the streak covers

        for day in days {
            let n = index(of: day)
            if let last = covered {
                if n <= last { continue }        // same day / backfill — already covered
                let gap = n - last - 1           // fully-missed days strictly between
                if gap == 0 {
                    current += 1
                } else if gap <= freezes {
                    freezes -= gap               // freezes bridge the gap; the run continues
                    current += 1
                } else {
                    current = 1                  // too big a gap — streak restarts here
                }
            } else {
                current = 1
            }
            covered = n
            longest = max(longest, current)
            // Earn one freeze at each 7-day milestone (capped).
            if current % daysPerFreeze == 0 {
                freezes = min(maxFreezes, freezes + 1)
            }
        }

        // Reconcile the gap between the last covered day and today. Today itself
        // is still "in progress", so it never counts as a missed day.
        var isAtRisk = false
        if let last = covered {
            let todayIndex = index(of: today)
            let gap = todayIndex - last - 1
            if gap > 0 {
                if gap <= freezes {
                    freezes -= gap               // freezes keep the streak alive
                } else {
                    current = 0                  // streak has lapsed
                }
            }
            isAtRisk = current > 0 && todayIndex > last
        }

        return ReviewStreak(
            current: current,
            longest: longest,
            freezesRemaining: freezes,
            isAtRiskToday: isAtRisk
        )
    }
}
