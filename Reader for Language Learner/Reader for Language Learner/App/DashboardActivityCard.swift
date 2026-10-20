//
//  DashboardActivityCard.swift
//  Reader for Language Learner
//
//  "Today's goal" on the home screen (Roadmap v19 Sprint 5, approved
//  mockup): reading and reviews, a ring each, the goal streak and the last
//  seven days as dots — ✓ both parts done, ½ one, empty none; the mark
//  reads without the colour. Right-click the card to change the goal. With
//  the reviews part off, one ring, as before.
//

import SwiftUI

struct DashboardActivityCard: View {
    let todayReadingTime: Double
    let last7Days: [ReadingSessionStore.DayStats]
    let readingStreak: Int
    var streakAtRisk: Bool = false

    @Environment(DailyGoalTracker.self) private var tracker: DailyGoalTracker?
    @AppStorage(StorageKey.dailyReadingGoalMinutes) private var goalMinutes: Int = 20
    @AppStorage(StorageKey.dailyGoalReviews) private var goalReviews = DailyGoal.Targets.defaultReviews

    static let goalChoices = DailyGoal.Targets.readingChoices

    private var targets: DailyGoal.Targets { DailyGoal.Targets(readingMinutes: goalMinutes, reviews: goalReviews) }

    /// Live from the tracker; from the card's own figures without one.
    private var day: DailyGoal.Day {
        tracker?.today ?? DailyGoal.Day(readingSeconds: todayReadingTime, reviews: 0, dueLeft: 0)
    }

    private var streak: Int { tracker?.streak ?? readingStreak }

    var body: some View {
        let day = day, targets = targets
        let readingDone = DailyGoal.readingDone(day, targets)
        let reviewsDone = DailyGoal.reviewsDone(day, targets)
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today's goal")
                    .font(DS.Typography.label)
                    .foregroundStyle(DS.Color.textPrimary)
                Spacer(minLength: DS.Spacing.sm)
                if streak > 0 {
                    Label(streak == 1 ? String(localized: "1-day streak") : String(localized: "\(streak)-day streak"),
                          systemImage: "flame.fill")
                        .font(DS.Typography.caption.weight(.semibold))
                        .foregroundStyle(DS.Color.warning)
                }
            }

            HStack(spacing: DS.Spacing.md) {
                part(
                    progress: min(1, day.readingSeconds / Double(max(1, targets.readingMinutes) * 60)),
                    done: readingDone,
                    value: "\(min(targets.readingMinutes, Int(day.readingSeconds / 60))) / \(targets.readingMinutes) min",
                    caption: readingDone ? String(localized: "Reading · done")
                        : String(localized: "Reading · \(DailyGoal.readingLeft(day, targets)) min left")
                )
                if targets.reviews > 0 {
                    part(
                        progress: reviewsDone ? 1 : min(1, Double(day.reviews) / Double(targets.reviews)),
                        done: reviewsDone,
                        value: "\(min(day.reviews, targets.reviews)) / \(targets.reviews)",
                        caption: reviewsDone
                            ? (day.reviews < targets.reviews ? String(localized: "Reviews · nothing left") : String(localized: "Reviews · done"))
                            : String(localized: "Reviews · \(DailyGoal.reviewsLeft(day, targets)) left")
                    )
                }
            }

            if let week = tracker?.week {
                HStack(spacing: DS.Spacing.xs) {
                    ForEach(week) { weekDay in
                        dayDot(weekDay)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(weekSummary(week)))
            }

            Text(hint(readingDone: readingDone, reviewsDone: reviewsDone))
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.textTertiary)
                .lineLimit(2)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
        .dsCard(padding: nil, radius: DS.Radius.md, stroke: .hairline)
        .contextMenu {
            Section("Daily Reading") {
                ForEach(DailyGoal.Targets.readingChoices, id: \.self) { minutes in
                    Toggle(String(localized: "\(minutes) minutes"), isOn: Binding(
                        get: { goalMinutes == minutes }, set: { if $0 { goalMinutes = minutes; tracker?.refresh() } }
                    ))
                }
            }
            Section("Daily Reviews") {
                ForEach(DailyGoal.Targets.reviewChoices, id: \.self) { count in
                    Toggle(count == 0 ? String(localized: "Off") : String(localized: "\(count) cards"), isOn: Binding(
                        get: { goalReviews == count }, set: { if $0 { goalReviews = count; tracker?.refresh() } }
                    ))
                }
            }
        }
        .help("Today's reading and reviews against your daily goal — right-click to change it")
        .accessibilityElement(children: .combine)
    }

    // MARK: Parts

    private func part(progress: Double, done: Bool, value: String, caption: String) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            ZStack {
                Circle().stroke(DS.Color.hairlineStrong, lineWidth: 3.5)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(done ? AnyShapeStyle(DS.Color.success) : AnyShapeStyle(DS.Gradient.goalRing),
                            style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if done {
                    Image(systemName: "checkmark")
                        .font(DS.Typography.icon(11, weight: .bold))
                        .foregroundStyle(DS.Color.success)
                } else {
                    Text("\(Int(progress * 100))%")
                        .font(DS.Typography.statNumber(9, weight: .semibold))
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }
            .frame(width: 34, height: 34)
            .animation(DS.Animation.spring, value: progress)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(DS.Typography.callout.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                Text(caption)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dayDot(_ day: DailyGoalTracker.WeekDay) -> some View {
        let (fill, mark): (Color, String) = switch day.status {
        case .full: (DS.Color.success, "✓")
        case .half: (DS.Color.warning, "½")
        case .none: (DS.Color.hairlineStrong, "")
        }
        return VStack(spacing: DS.Spacing.hairline) {
            Text(mark)
                .font(DS.Typography.caption2.weight(.bold))
                .foregroundStyle(day.status == .none ? DS.Color.textTertiary : .white)
                .frame(width: 18, height: 18)
                .background(day.isToday && day.status == .none ? Color.clear : fill, in: Circle())
                .overlay(Circle().strokeBorder(day.isToday ? DS.Color.accent : .clear,
                                               style: StrokeStyle(lineWidth: 1.5, dash: day.status == .none ? [2, 2] : [])))
            Text(day.id.formatted(.dateTime.weekday(.narrow)))
                .font(DS.Typography.micro(8))
                .foregroundStyle(day.isToday ? DS.Color.accent : DS.Color.textTertiary)
        }
    }

    private func hint(readingDone: Bool, reviewsDone: Bool) -> String {
        switch (readingDone, reviewsDone || targets.reviews == 0) {
        case (true, true):   return String(localized: "Today's goal is done.")
        case (false, true):  return String(localized: "Read \(DailyGoal.readingLeft(day, targets)) more minutes to finish today.")
        case (true, false):  return String(localized: "Review \(DailyGoal.reviewsLeft(day, targets)) more cards to finish today.")
        case (false, false): return String(localized: "Read a little and review a few cards to keep the streak.")
        }
    }

    private func weekSummary(_ week: [DailyGoalTracker.WeekDay]) -> String {
        let full = week.filter { $0.status == .full }.count
        return String(localized: "Goal done on \(full) of the last 7 days")
    }
}
