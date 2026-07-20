//
//  ReadingStatsView.swift
//  Reader for Language Learner
//
//  Reading statistics sidebar panel:
//  • Today's reading time (live, updates each second)
//  • 7-day bar chart
//  • Total stats grid
//

import Charts
import SwiftUI

struct ReadingStatsView: View {
    var sessionStore: ReadingSessionStore
    var savedWordsStore: SavedWordsStore

    // Ticks each second to keep the live timer fresh (no Combine needed)
    @State private var tick = Date()

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                todayCard
                weeklyChart
                reviewActivityCard
                vocabularyGrowthCard
                masteryDistributionCard
                learningGrid
                totalsGrid
            }
            .padding(DS.Spacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                tick = Date()
            }
        }
    }

    // MARK: - Today Card

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("TODAY")
                .dsOverlineLabel()

            HStack(alignment: .lastTextBaseline, spacing: DS.Spacing.xs) {
                Text(formatMinutes(sessionStore.todayReadingTime))
                    .font(DS.Typography.statNumber(42))
                    .foregroundStyle(DS.Color.textPrimary)
                    .contentTransition(.numericText(countsDown: false))
                    .id(tick)   // force re-render each tick
                Text("min")
                    .font(DS.Typography.title)
                    .foregroundStyle(DS.Color.textTertiary)
            }

            if let session = sessionStore.activeSession {
                HStack(spacing: DS.Spacing.xs) {
                    Circle()
                        .fill(DS.Color.success)
                        .frame(width: 6, height: 6)
                        .symbolEffect(.pulse, options: .repeating)
                    Text("Reading \(session.pdfFilename)")
                        .font(DS.Typography.caption2)
                        .foregroundStyle(DS.Color.success)
                        .lineLimit(1)
                }
            }

            let streak = sessionStore.currentStreak
            if streak > 0 {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(DS.Color.warning)
                        .font(DS.Typography.icon(11))
                    Text("\(streak) day streak")
                        .font(DS.Typography.caption2.weight(.semibold))
                        .foregroundStyle(DS.Color.textSecondary)
                    let longest = sessionStore.longestStreak
                    if longest > streak {
                        Text("· best \(longest)")
                            .font(DS.Typography.caption2)
                            .foregroundStyle(DS.Color.textTertiary)
                    }
                }
            }
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard(padding: nil, stroke: .none, shadow: DS.Shadow.subtle)
    }

    // MARK: - 7-Day Chart

    private var weeklyChart: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("LAST 7 DAYS")
                .dsOverlineLabel()

            let data = sessionStore.last7Days
            let maxVal = max(data.map(\.seconds).max() ?? 1, 60)

            Chart(data) { day in
                BarMark(
                    x: .value("Day",     day.label),
                    y: .value("Minutes", day.seconds / 60)
                )
                .foregroundStyle(
                    day.day == Calendar.current.startOfDay(for: Date())
                    ? DS.Color.accent
                    : DS.Color.accentMuted
                )
                .cornerRadius(DS.Radius.xs)
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { val in
                    AxisGridLine().foregroundStyle(DS.Color.hairlineStrong)
                    AxisValueLabel {
                        if let v = val.as(Double.self) {
                            Text(String(format: "%dm", Int(v)))
                                .font(DS.Typography.caption2)
                                .foregroundStyle(DS.Color.textTertiary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { val in
                    AxisValueLabel {
                        if let s = val.as(String.self) {
                            Text(s)
                                .font(DS.Typography.caption2)
                                .foregroundStyle(DS.Color.textTertiary)
                        }
                    }
                }
            }
            .chartYScale(domain: 0...(maxVal / 60 * 1.2))
            .frame(height: 100)
        }
        .padding(DS.Spacing.md)
        .dsCard(padding: nil, stroke: .none, shadow: DS.Shadow.subtle)
    }

    // MARK: - Review Activity Heatmap

    @ViewBuilder
    private var reviewActivityCard: some View {
        let activity = savedWordsStore.reviewActivity(days: 365)
        if activity.contains(where: { $0.count > 0 }) {
            ReviewHeatmapView(activity: activity)
                .padding(DS.Spacing.md)
                .dsCard(padding: nil, stroke: .none, shadow: DS.Shadow.subtle)
        }
    }

    // MARK: - Vocabulary Growth

    @ViewBuilder
    private var vocabularyGrowthCard: some View {
        let points = vocabularyGrowth
        if points.count >= 2 {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                Text("VOCABULARY GROWTH")
                    .dsOverlineLabel()

                Chart(points) { point in
                    AreaMark(
                        x: .value("Day", point.date),
                        y: .value("Words", point.total)
                    )
                    .foregroundStyle(DS.Gradient.chartFade)
                    LineMark(
                        x: .value("Day", point.date),
                        y: .value("Words", point.total)
                    )
                    .foregroundStyle(DS.Color.accent)
                    .interpolationMethod(.monotone)
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine().foregroundStyle(DS.Color.hairlineStrong)
                        AxisValueLabel()
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .frame(height: 110)
            }
            .padding(DS.Spacing.md)
            .dsCard(padding: nil, stroke: .none, shadow: DS.Shadow.subtle)
        }
    }

    /// Cumulative saved-word count over time, sampled per day a word was saved.
    private var vocabularyGrowth: [VocabPoint] {
        let sorted = savedWordsStore.words.map(\.savedAt).sorted()
        guard !sorted.isEmpty else { return [] }
        let calendar = Calendar.current
        var byDay: [Date: Int] = [:]
        for date in sorted {
            let day = calendar.startOfDay(for: date)
            byDay[day, default: 0] += 1
        }
        var running = 0
        return byDay.keys.sorted().map { day in
            running += byDay[day] ?? 0
            return VocabPoint(date: day, total: running)
        }
    }

    // MARK: - Mastery Distribution

    @ViewBuilder
    private var masteryDistributionCard: some View {
        let slices = masterySlices
        if slices.contains(where: { $0.count > 0 }) {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                Text("MASTERY")
                    .dsOverlineLabel()

                Chart(slices) { slice in
                    BarMark(
                        x: .value("Count", slice.count),
                        y: .value("Level", slice.label)
                    )
                    .foregroundStyle(slice.color)
                    .cornerRadius(DS.Radius.xs)
                    .annotation(position: .trailing) {
                        if slice.count > 0 {
                            Text("\(slice.count)")
                                .font(DS.Typography.caption2)
                                .foregroundStyle(DS.Color.textTertiary)
                        }
                    }
                }
                .chartXAxis(.hidden)
                .frame(height: 92)
            }
            .padding(DS.Spacing.md)
            .dsCard(padding: nil, stroke: .none, shadow: DS.Shadow.subtle)
        }
    }

    private var masterySlices: [MasterySlice] {
        [
            MasterySlice(label: "New", count: savedWordsStore.newCount, color: DS.Color.accent),
            MasterySlice(label: "Learning", count: savedWordsStore.learningCount, color: DS.Color.warning),
            MasterySlice(label: "Mastered", count: savedWordsStore.masteredCount, color: DS.Color.success)
        ]
    }

    // MARK: - Totals Grid

    private var learningGrid: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("LEARNING")
                .dsOverlineLabel()

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DS.Spacing.sm) {
                statCell(
                    icon: "clock.badge.exclamationmark",
                    value: "\(savedWordsStore.pendingReviewCount)",
                    label: "Pending review",
                    iconColor: DS.Color.warning
                )
                statCell(
                    icon: "checkmark.circle.fill",
                    value: "\(savedWordsStore.reviewedTodayCount)",
                    label: "Reviewed today",
                    iconColor: DS.Color.accent
                )
                statCell(
                    icon: "checkmark.seal.fill",
                    value: "\(savedWordsStore.masteredCount)",
                    label: "Mastered words",
                    iconColor: DS.Color.success
                )
                statCell(
                    icon: "brain",
                    value: "\(savedWordsStore.learningCount)",
                    label: "Learning now",
                    iconColor: DS.Color.warning
                )
            }
        }
    }

    private var totalsGrid: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("ALL TIME")
                .dsOverlineLabel()

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DS.Spacing.sm) {
                statCell(
                    icon: "clock.fill",
                    value: formatTotalTime(sessionStore.totalReadingTime),
                    label: "Total read"
                )
                statCell(
                    icon: "star.fill",
                    value: "\(savedWordsStore.words.count)",
                    label: "Words saved",
                    iconColor: DS.Color.star
                )
                statCell(
                    icon: "doc.text.fill",
                    value: "\(sessionStore.uniqueDocumentsRead)",
                    label: "Docs opened"
                )
                statCell(
                    icon: "sparkles",
                    value: "\(savedWordsStore.newCount)",
                    label: "New words"
                )
            }
        }
    }

    private func statCell(
        icon: String,
        value: String,
        label: String,
        iconColor: SwiftUI.Color = DS.Color.accent
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Image(systemName: icon)
                .font(DS.Typography.icon(14))
                .foregroundStyle(iconColor)
            Text(value)
                .font(DS.Typography.headline)
                .foregroundStyle(DS.Color.textPrimary)
            Text(label)
                .font(DS.Typography.caption2)
                .foregroundStyle(DS.Color.textTertiary)
        }
        .padding(DS.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard(padding: nil, stroke: .none, shadow: DS.Shadow.subtle)
    }

    // MARK: - Formatters

    private func formatMinutes(_ seconds: Double) -> String {
        String(format: "%.0f", seconds / 60)
    }

    private func formatTotalTime(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}

// MARK: - Chart Models

private struct VocabPoint: Identifiable {
    let date: Date
    let total: Int
    var id: Date { date }
}

private struct MasterySlice: Identifiable {
    let label: String
    let count: Int
    let color: Color
    var id: String { label }
}
