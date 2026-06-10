//
//  WorkspaceSummaryView.swift
//  Reader for Language Learner
//

import SwiftUI

struct WorkspaceSummaryView: View {
    let todayReadingTime: Double
    let pendingReviewCount: Int
    let reviewedTodayCount: Int
    let noteCount: Int
    let savedWordCount: Int
    let bookmarkCount: Int
    var reviewActivity: [SavedWordsStore.ReviewActivityDay] = []
    var compact = false
    var onOpenPDF: (() -> Void)?
    var onReview: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? DS.Spacing.sm : DS.Spacing.md) {
            if !compact {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text("Workspace")
                            .font(DS.Typography.headline)
                            .foregroundStyle(DS.Color.textPrimary)
                        Text(summaryText)
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Color.textTertiary)
                    }

                    Spacer()
                }
            }

            metrics

            if !compact && !reviewActivity.isEmpty && reviewActivity.contains(where: { $0.count > 0 }) {
                ReviewHeatmapView(activity: reviewActivity)
            }

            if onOpenPDF != nil || onReview != nil {
                HStack(spacing: DS.Spacing.sm) {
                    if let onOpenPDF {
                        LearningActionRow(
                            title: "Open PDF",
                            subtitle: "Start a new reading session",
                            icon: "folder.badge.plus",
                            action: onOpenPDF
                        )
                    }
                    if let onReview {
                        LearningActionRow(
                            title: pendingReviewCount > 0 ? "Review \(pendingReviewCount)" : "Open Review",
                            subtitle: pendingReviewCount > 0 ? "Words due now" : "Practice saved words",
                            icon: "brain.head.profile",
                            action: onReview
                        )
                        .disabled(savedWordCount == 0)
                    }
                }
            }
        }
        .padding(compact ? DS.Spacing.sm : DS.Spacing.md)
        .background(DS.Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: compact ? DS.Radius.sm : DS.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: compact ? DS.Radius.sm : DS.Radius.md)
                .strokeBorder(DS.Color.separator.opacity(compact ? 0.18 : 0.26), lineWidth: 0.7)
        )
    }

    private var metrics: some View {
        DashboardMetricStrip {
            DocumentMetricChip(icon: "clock", value: Self.durationFormatter.string(from: todayReadingTime) ?? "0m", label: "Today", tint: DS.Color.accent)
            DocumentMetricChip(icon: pendingReviewCount > 0 ? "clock.badge.exclamationmark" : "checkmark.seal", value: "\(pendingReviewCount)", label: "Due", tint: pendingReviewCount > 0 ? DS.Color.warning : DS.Color.success)
            DocumentMetricChip(icon: "checkmark.circle", value: "\(reviewedTodayCount)", label: "Reviewed", tint: DS.Color.success)
            DocumentMetricChip(icon: "note.text", value: "\(noteCount)", label: "Notes", tint: .purple)
            DocumentMetricChip(icon: "star", value: "\(savedWordCount)", label: "Saved", tint: .yellow)
            DocumentMetricChip(icon: "bookmark", value: "\(bookmarkCount)", label: "Marks", tint: .purple)
        }
    }

    private var summaryText: String {
        if pendingReviewCount > 0 {
            return "\(pendingReviewCount) words are ready for review."
        }
        if savedWordCount > 0 {
            return "Keep reading, saving, and reviewing from one place."
        }
        return "Open a PDF, select text, then save words and notes as you read."
    }

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        formatter.zeroFormattingBehavior = .dropAll
        return formatter
    }()
}

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

struct DashboardMetricStrip<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                content
            }
        }
        .background(DS.Color.surfaceInset.opacity(0.45))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(DS.Color.accent.opacity(0.55))
                .frame(height: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.sm)
                .strokeBorder(DS.Color.separator.opacity(0.18), lineWidth: 1)
        )
    }
}

struct DocumentMetricChip: View {
    let icon: String
    let value: String
    let label: String
    var tint: Color = DS.Color.textSecondary

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 12)
                    Text(label)
                        .font(DS.Typography.caption2)
                        .foregroundStyle(DS.Color.textTertiary)
                        .lineLimit(1)
                }
                Text(value.isEmpty ? "0" : value)
                    .font(DS.Typography.caption.weight(.semibold))
                    .foregroundStyle(DS.Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
        .frame(minWidth: 104, alignment: .leading)
        .background(tint.opacity(0.045))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(DS.Color.separator.opacity(0.18))
                .frame(width: 1)
        }
    }
}

struct LearningActionRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Color.accent)
                    .frame(width: 22, height: 22)
                    .background(DS.Color.accentSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xs))

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(DS.Typography.caption.weight(.semibold))
                        .foregroundStyle(DS.Color.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(DS.Typography.caption2)
                        .foregroundStyle(DS.Color.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: DS.Spacing.xs)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(DS.Color.textTertiary)
            }
            .padding(DS.Spacing.sm)
            .background(DS.Color.surfaceInset.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
        }
        .buttonStyle(.plain)
    }
}
