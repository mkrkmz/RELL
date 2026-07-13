//
//  DashboardActivityCard.swift
//  Reader for Language Learner
//
//  Dashboard card combining the daily reading goal ring, reading streak,
//  and a 7-day activity mini chart. Right-click the card to change the goal.
//

import Charts
import SwiftUI

struct DashboardActivityCard: View {
    let todayReadingTime: Double
    let last7Days: [ReadingSessionStore.DayStats]
    let readingStreak: Int
    var streakAtRisk: Bool = false

    @AppStorage("dailyReadingGoalMinutes") private var goalMinutes: Int = 20

    private static let goalChoices = [10, 15, 20, 30, 45, 60]

    private var todayMinutes: Int {
        Int(todayReadingTime / 60)
    }

    private var progress: Double {
        guard goalMinutes > 0 else { return 0 }
        return min(1, todayReadingTime / Double(goalMinutes * 60))
    }

    private var goalReached: Bool {
        progress >= 1
    }

    var body: some View {
        HStack(spacing: DS.Spacing.lg) {
            goalRing

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(goalReached ? "Daily goal reached" : "\(todayMinutes) of \(goalMinutes) min today")
                    .font(DS.Typography.label)
                    .foregroundStyle(DS.Color.textPrimary)
                    .lineLimit(1)

                if readingStreak > 0 {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(streakAtRisk ? DS.Color.warning : (goalReached ? DS.Color.warning : DS.Color.textTertiary))
                        if streakAtRisk {
                            Text(readingStreak == 1 ? "1-day streak · read today to keep it" : "\(readingStreak)-day streak · read today to keep it")
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Color.warning)
                        } else {
                            Text(readingStreak == 1 ? "1-day streak" : "\(readingStreak)-day streak")
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Color.textTertiary)
                        }
                    }
                } else {
                    Text("Read a little every day")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                }
            }

            Spacer(minLength: DS.Spacing.lg)

            weeklyChart
                .frame(width: 190, height: 48)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
        .background(DS.Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .strokeBorder(DS.Color.hairline, lineWidth: 1)
        )
        .contextMenu {
            Section("Daily Goal") {
                ForEach(Self.goalChoices, id: \.self) { minutes in
                    Button {
                        goalMinutes = minutes
                    } label: {
                        if minutes == goalMinutes {
                            Label("\(minutes) minutes", systemImage: "checkmark")
                        } else {
                            Text("\(minutes) minutes")
                        }
                    }
                }
            }
        }
        .help("Today's reading vs your daily goal — right-click to change the goal")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            goalReached
            ? "Daily reading goal reached"
            : "\(todayMinutes) of \(goalMinutes) minutes read today"
        )
    }

    // MARK: - Goal Ring

    private var goalRing: some View {
        ZStack {
            Circle()
                .stroke(DS.Color.hairlineStrong, lineWidth: 3.5)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    goalReached ? DS.Color.success : DS.Color.accent,
                    style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            if goalReached {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(DS.Color.success)
                    .symbolEffect(.bounce, value: goalReached)
            } else {
                Text("\(Int(progress * 100))%")
                    .font(DS.Typography.statNumber(9, weight: .semibold))
                    .foregroundStyle(DS.Color.textSecondary)
            }
        }
        .frame(width: 38, height: 38)
        .animation(DS.Animation.spring, value: progress)
    }

    // MARK: - Weekly Chart

    private var weeklyChart: some View {
        Chart(last7Days) { day in
            BarMark(
                x: .value("Day", day.label),
                y: .value("Minutes", max(day.seconds / 60, 0))
            )
            .foregroundStyle(
                Calendar.current.isDateInToday(day.day)
                ? DS.Color.accent
                : DS.Color.accentMuted
            )
            .cornerRadius(2)

            if goalMinutes > 0 {
                RuleMark(y: .value("Goal", goalMinutes))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(DS.Color.separator)
            }
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let label = value.as(String.self) {
                        Text(label.prefix(1))
                            .font(DS.Typography.micro(8))
                            .foregroundStyle(DS.Color.textTertiary)
                    }
                }
            }
        }
        .chartYScale(domain: 0...max(Double(goalMinutes), (last7Days.map { $0.seconds / 60 }.max() ?? 0) * 1.15, 1))
        .accessibilityLabel("Reading minutes for the last 7 days")
    }
}
