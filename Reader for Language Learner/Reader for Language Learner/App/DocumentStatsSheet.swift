//
//  DocumentStatsSheet.swift
//  Reader for Language Learner
//
//  A document's reading statistics. Split out of LibraryView.swift (v20 S0),
//  unchanged.
//

import AppKit
import SwiftUI

// MARK: - Document Stats

struct DocumentStats {
    var readingTime: Double
    var savedWords: Int
    var dueWords: Int
    var notes: Int
    var bookmarks: Int
    var progress: Double?
    var pageLabel: String
    /// Whole-book vocabulary coverage, once the book has been opened at least
    /// once with words saved (L-V2).
    var coverage: LexicalProfile?
}

struct DocumentStatsSheet: View {
    let document: RecentDocument
    let stats: DocumentStats

    @Environment(\.dismiss) private var dismiss

    private var displayTitle: String {
        document.displayTitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .foregroundStyle(DS.Color.accent)
                Text(displayTitle)
                    .font(DS.Typography.headline)
                    .foregroundStyle(DS.Color.textPrimary)
                    .lineLimit(1)
                Spacer()
                Button("Close", systemImage: "xmark") { dismiss() }
                    .buttonStyle(.dsIconSecondary)
                    .keyboardShortcut(.cancelAction)
                    .foregroundStyle(DS.Color.textTertiary)
            }
            .padding(DS.Spacing.lg)

            Divider()

            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                if let progress = stats.progress {
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        HStack {
                            Text(stats.pageLabel)
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Color.textSecondary)
                            Spacer()
                            Text("\(Int(progress * 100))%")
                                .font(DS.Typography.caption.weight(.semibold))
                                .foregroundStyle(DS.Color.accent)
                        }
                        DSProgressBar(value: progress, height: 5)
                            .clipShape(Capsule())
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DS.Spacing.sm) {
                    statCell(icon: "clock", value: formattedTime, label: "Read", tint: DS.Color.accent)
                    statCell(icon: "star", value: "\(stats.savedWords)", label: "Saved words", tint: DS.Color.star)
                    statCell(icon: "clock.badge.exclamationmark", value: "\(stats.dueWords)", label: "Due", tint: DS.Color.warning)
                    statCell(icon: "note.text", value: "\(stats.notes)", label: "Notes", tint: .purple)
                    statCell(icon: "bookmark", value: "\(stats.bookmarks)", label: "Bookmarks", tint: .teal)
                    if let coverage = stats.coverage {
                        statCell(
                            icon: "text.book.closed",
                            value: "\(Int(coverage.knownShare * 100))%",
                            label: "Words you know",
                            tint: DS.Color.coverageTint(for: coverage.difficulty)
                        )
                    }
                }
            }
            .padding(DS.Spacing.lg)

            Spacer(minLength: 0)
        }
        .frame(width: 360, height: 360)
    }

    private var formattedTime: String {
        let total = Int(stats.readingTime)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "—"
    }

    /// `label` is a `LocalizedStringKey`: `Text(String)` never reaches the
    /// string catalog, so a String here ships English no matter what the
    /// catalog says (CLAUDE.md).
    private func statCell(icon: String, value: String, label: LocalizedStringKey, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Image(systemName: icon)
                .font(DS.Typography.icon(13))
                .foregroundStyle(tint)
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
    }
}
