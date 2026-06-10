//
//  ReviewHeatmapView.swift
//  Reader for Language Learner
//
//  GitHub-style yearly review activity heatmap, shown in the Stats sidebar.
//

import SwiftUI

struct ReviewHeatmapView: View {
    let activity: [SavedWordsStore.ReviewActivityDay]

    private let cellSize: CGFloat = 6
    private let cellSpacing: CGFloat = 2

    private var maxCount: Int {
        max(activity.map(\.count).max() ?? 0, 1)
    }

    private var totalCount: Int {
        activity.reduce(0) { $0 + $1.count }
    }

    private var reviewedDays: Int {
        activity.filter { $0.count > 0 }.count
    }

    private var dailyAverage: Int {
        guard !activity.isEmpty else { return 0 }
        return Int((Double(totalCount) / Double(activity.count)).rounded())
    }

    private var learnedPercent: Int {
        guard !activity.isEmpty else { return 0 }
        return Int((Double(reviewedDays) / Double(activity.count) * 100).rounded())
    }

    private var longestStreak: Int {
        streaks.longest
    }

    private var currentStreak: Int {
        streaks.current
    }

    private var calendarWeeks: [[HeatmapCalendarCell]] {
        let cells = calendarCells
        return stride(from: 0, to: cells.count, by: 7).map { start in
            let end = min(start + 7, cells.count)
            return Array(cells[start..<end])
        }
    }

    private var calendarCells: [HeatmapCalendarCell] {
        guard let firstDate = activity.first?.date else { return [] }
        let leadingBlankCount = Calendar.current.component(.weekday, from: firstDate) - 1
        let leading = (0..<leadingBlankCount).map { HeatmapCalendarCell(id: "blank-\($0)", day: nil) }
        let days = activity.map { HeatmapCalendarCell(id: Self.cellIDFormatter.string(from: $0.date), day: $0) }
        return leading + days
    }

    private var yearLabel: String {
        guard let lastDate = activity.last?.date else { return "" }
        return Self.yearFormatter.string(from: lastDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Label("Review Activity", systemImage: "calendar")
                    .font(DS.Typography.caption.weight(.semibold))
                    .foregroundStyle(DS.Color.textSecondary)
                Spacer()
                Text(yearLabel)
                    .font(DS.Typography.caption2)
                    .foregroundStyle(DS.Color.textTertiary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: cellSpacing) {
                    ForEach(Array(calendarWeeks.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: cellSpacing) {
                            ForEach(week) { cell in
                                if let day = cell.day {
                                    RoundedRectangle(cornerRadius: 1.3)
                                        .fill(color(for: day.count))
                                        .frame(width: cellSize, height: cellSize)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 1.3)
                                                .strokeBorder(DS.Color.separator.opacity(0.08), lineWidth: 0.4)
                                        )
                                        .help(helpText(for: day))
                                        .accessibilityLabel(helpText(for: day))
                                } else {
                                    Color.clear
                                        .frame(width: cellSize, height: cellSize)
                                }
                            }
                        }
                    }
                }
                .frame(height: (cellSize * 7) + (cellSpacing * 6), alignment: .topLeading)
            }

            HStack(spacing: DS.Spacing.md) {
                heatmapStat("Avg", "\(dailyAverage)/day")
                heatmapStat("Days", "\(learnedPercent)%")
                heatmapStat("Best", "\(longestStreak)d")
                heatmapStat("Now", "\(currentStreak)d")
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .padding(.top, DS.Spacing.xs)
    }

    private func color(for count: Int) -> Color {
        guard count > 0 else { return DS.Color.separator.opacity(0.2) }
        let intensity = 0.32 + (0.58 * Double(count) / Double(maxCount))
        return DS.Color.success.opacity(intensity)
    }

    private func heatmapStat(_ label: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .foregroundStyle(DS.Color.textTertiary)
            Text(value)
                .foregroundStyle(DS.Color.accent)
                .fontWeight(.semibold)
        }
        .font(DS.Typography.caption2)
    }

    private var streaks: (longest: Int, current: Int) {
        var longest = 0
        var run = 0

        for day in activity {
            if day.count > 0 {
                run += 1
                longest = max(longest, run)
            } else {
                run = 0
            }
        }

        var current = 0
        for day in activity.reversed() {
            if day.count > 0 {
                current += 1
            } else if current > 0 {
                break
            }
        }

        return (longest, current)
    }

    private func helpText(for day: SavedWordsStore.ReviewActivityDay) -> String {
        let date = Self.dateFormatter.string(from: day.date)
        if day.count == 1 {
            return "1 review on \(date)"
        }
        return "\(day.count) reviews on \(date)"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let yearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter
    }()

    private static let cellIDFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct HeatmapCalendarCell: Identifiable {
    let id: String
    let day: SavedWordsStore.ReviewActivityDay?
}
