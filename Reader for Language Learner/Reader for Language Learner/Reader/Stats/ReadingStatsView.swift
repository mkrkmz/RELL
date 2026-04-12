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
                    .font(.system(size: 42, weight: .bold, design: .rounded))
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
                        .foregroundStyle(.orange)
                        .font(.system(size: 11))
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
        .background(DS.Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        .dsShadow(DS.Shadow.subtle)
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
                    AxisGridLine().foregroundStyle(DS.Color.separator.opacity(0.4))
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
        .background(DS.Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        .dsShadow(DS.Shadow.subtle)
    }

    // MARK: - Totals Grid

    private var totalsGrid: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("ALL TIME")
                .dsOverlineLabel()

            HStack(spacing: DS.Spacing.sm) {
                statCell(
                    icon: "clock.fill",
                    value: formatTotalTime(sessionStore.totalReadingTime),
                    label: "Total read"
                )
                statCell(
                    icon: "star.fill",
                    value: "\(savedWordsStore.words.count)",
                    label: "Words saved",
                    iconColor: .yellow
                )
                statCell(
                    icon: "doc.text.fill",
                    value: "\(sessionStore.uniqueDocumentsRead)",
                    label: "Docs opened"
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
                .font(.system(size: 14))
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
        .background(DS.Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        .dsShadow(DS.Shadow.subtle)
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
