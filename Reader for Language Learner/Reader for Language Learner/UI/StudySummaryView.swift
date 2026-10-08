//
//  StudySummaryView.swift
//  Reader for Language Learner
//
//  How a study-room session ended (Roadmap v15 Sprint 2): what you
//  remembered, what you struggled with — one click to go over those again —
//  what settled, and what tomorrow brings.
//

import SwiftUI

struct StudySummaryView: View {
    let session: QuizSession
    var store: SavedWordsStore
    let mode: QuizMode
    let onStudyAgain: ([SavedWord]) -> Void
    let onMore: () -> Void
    let onClose: () -> Void

    var body: some View {
        let summary = StudySummary(answers: session.answers, startedAt: session.startedAt)
        ScrollView(.vertical) {
            HStack(alignment: .top, spacing: DS.Spacing.xl) {
                overview(summary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                lists(summary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: 920)
            .padding(DS.Spacing.xl)
            .frame(maxWidth: .infinity)
        }
    }

    private func overview(_ summary: StudySummary) -> some View {
        let answered = summary.remembered + summary.struggled.count
        return VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text(mode.isRoundBased
                 ? String(localized: "Practice done")
                 : answered == 1 ? String(localized: "1 word done") : String(localized: "\(answered) words done"))
                .font(DS.Typography.largeTitle)

            if mode.isRoundBased {
                if let accuracy = session.accuracy {
                    Text("\(Int((accuracy * 100).rounded()))% of your pairs were right the first time.")
                        .foregroundStyle(DS.Color.textSecondary)
                }
            } else {
                Grid(horizontalSpacing: DS.Spacing.sm) {
                    GridRow {
                        stat("\(summary.remembered)", String(localized: "remembered"), DS.Color.success)
                        stat("\(summary.struggled.count)", String(localized: "marked again"), DS.Color.danger)
                        stat(Self.durationText(summary.duration), String(localized: "took"), DS.Color.textPrimary)
                    }
                }
            }

            footnote(summary)
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: DS.Spacing.sm) {
                let again = summary.struggled.compactMap { store.word(withID: $0.id) }
                if !again.isEmpty {
                    Button(again.count == 1 ? String(localized: "Go Over the 1 You Struggled With")
                                            : String(localized: "Go Over the \(again.count) You Struggled With")) {
                        onStudyAgain(again)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
                Button("More Words", action: onMore)
                Button("Close", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
            .controlSize(.large)
        }
    }

    private func footnote(_ summary: StudySummary) -> Text {
        let streak = store.reviewStreak().current
        let tomorrow = StudyPlan.comingDueTomorrow(in: store.words)
            + StudyPlan.dueReviewCount(in: store.words)
        var parts: [String] = []
        if !summary.settled.isEmpty {
            parts.append(String(localized: "\(summary.settled.count) words now come back after a week or more."))
        }
        parts.append(String(localized: "\(tomorrow) words will be waiting by tomorrow."))
        if streak > 0 { parts.append(String(localized: "Streak: \(streak) days.")) }
        return Text(parts.joined(separator: " "))
    }

    private func stat(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(DS.Typography.statNumber(22))
                .foregroundStyle(tint)
            Text(label)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }

    @ViewBuilder
    private func lists(_ summary: StudySummary) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            if !summary.struggled.isEmpty {
                list(String(localized: "YOU STRUGGLED WITH"), summary.struggled)
            }
            if !summary.settled.isEmpty {
                list(String(localized: "SETTLED"), summary.settled)
            }
        }
    }

    private func list(_ title: String, _ lines: [StudySummary.Line]) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(title).dsOverlineLabel()
            VStack(spacing: 0) {
                ForEach(Array(lines.prefix(12).enumerated()), id: \.element.id) { index, line in
                    if index > 0 { Divider() }
                    HStack(spacing: DS.Spacing.sm) {
                        Text(line.term).font(DS.Typography.callout.weight(.medium))
                        if let meaning = store.word(withID: line.id).flatMap(SavedWordRow.oneLineMeaning(of:)) {
                            Text(MarkdownUtils.sanitizeLLMOutput(meaning))
                                .font(DS.Typography.callout)
                                .foregroundStyle(DS.Color.textSecondary)
                        }
                        Spacer(minLength: DS.Spacing.sm)
                        if let next = line.nextReviewAt {
                            Text(StudyPlan.intervalLabel(from: Date(), to: next))
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Color.textTertiary)
                                .monospacedDigit()
                        }
                    }
                    .lineLimit(1)
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.sm)
                }
            }
            .dsCard(padding: nil)
        }
    }

    static func durationText(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .short
        formatter.allowedUnits = seconds < 60 ? [.second] : [.minute]
        formatter.maximumUnitCount = 1
        return formatter.string(from: max(1, seconds)) ?? ""
    }
}
