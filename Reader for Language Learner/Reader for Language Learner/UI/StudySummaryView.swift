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

    @Environment(\.openWindow) private var openWindow
    @FocusState private var focusedLine: UUID?

    // v18 S5 (approved mockup): a small celebration — the share remembered
    // in a ring, the session's trail, four coloured tiles — and lists you
    // can walk with the keys, each word opening in the notebook.
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
        .background(
            ZStack {
                RadialGradient(colors: [DS.Color.success.opacity(0.12), .clear], center: .topLeading, startRadius: 0, endRadius: 520)
                RadialGradient(colors: [DS.Color.accent.opacity(0.10), .clear], center: .topTrailing, startRadius: 0, endRadius: 520)
            }
            .ignoresSafeArea()
        )
    }

    private func overview(_ summary: StudySummary) -> some View {
        let answered = summary.remembered + summary.struggled.count
        let ratings = session.answers.map(\.rating)
        return VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.lg) {
                if !mode.isRoundBased, answered > 0 {
                    rememberedRing(Double(summary.remembered) / Double(answered))
                }
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(mode.isRoundBased
                         ? String(localized: "Practice done")
                         : answered == 1 ? String(localized: "1 word done") : String(localized: "\(answered) words done"))
                        .font(DS.Typography.largeTitle)
                    if mode.isRoundBased, let accuracy = session.accuracy {
                        Text("\(Int((accuracy * 100).rounded()))% of your pairs were right the first time.")
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                    if !ratings.isEmpty {
                        SessionTrail(ratings: ratings, total: ratings.count)
                            .frame(maxWidth: 280)
                    }
                }
            }

            if !mode.isRoundBased {
                Grid(horizontalSpacing: DS.Spacing.sm) {
                    GridRow {
                        tile("checkmark", "\(summary.remembered)", String(localized: "remembered"), DS.Color.success)
                        tile("arrow.counterclockwise", "\(summary.struggled.count)", String(localized: "marked again"), DS.Color.danger)
                        tile("clock", Self.durationText(summary.duration), String(localized: "took"), DS.Color.accent)
                        tile("flame.fill", "\(store.reviewStreak().current)", String(localized: "day streak"), DS.Color.warning)
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
                    .help("Return")
                }
                Button("More Words", action: onMore)
                    .keyboardShortcut("m", modifiers: [])
                    .help("M")
                Button("Close", action: onClose)
                    .keyboardShortcut(.cancelAction)
                    .help("Esc")
            }
            .controlSize(.large)
        }
    }

    private func rememberedRing(_ share: Double) -> some View {
        ZStack {
            Circle().stroke(DS.Color.hairlineStrong, lineWidth: 9)
            Circle()
                .trim(from: 0, to: share)
                .stroke(DS.Color.success, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(share, format: .percent.precision(.fractionLength(0)))
                    .font(DS.Typography.statNumber(20))
                Text("remembered")
                    .font(DS.Typography.caption2)
                    .foregroundStyle(DS.Color.textSecondary)
            }
        }
        .frame(width: 92, height: 92)
        .accessibilityElement(children: .combine)
    }

    private func footnote(_ summary: StudySummary) -> Text {
        let tomorrow = StudyPlan.comingDueTomorrow(in: store.words)
            + StudyPlan.dueReviewCount(in: store.words)
        var parts: [String] = []
        if !summary.settled.isEmpty {
            parts.append(String(localized: "\(summary.settled.count) words now come back after a week or more."))
        }
        parts.append(String(localized: "\(tomorrow) words will be waiting by tomorrow."))
        return Text(parts.joined(separator: " "))
    }

    /// A coloured tile: its mark and its label say what the number is.
    private func tile(_ symbol: String, _ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(value, systemImage: symbol)
                .font(DS.Typography.statNumber(20))
                .foregroundStyle(tint)
                .labelStyle(.titleAndIcon)
            Text(label)
                .font(DS.Typography.caption.weight(.semibold))
                .foregroundStyle(DS.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Spacing.sm)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: DS.Radius.md))
        .accessibilityElement(children: .combine)
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
            if !summary.struggled.isEmpty || !summary.settled.isEmpty {
                Text("Choose a word to open it in the notebook.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
            }
        }
    }

    private func list(_ title: String, _ lines: [StudySummary.Line]) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(title).dsOverlineLabel()
            VStack(spacing: 0) {
                ForEach(Array(lines.prefix(12).enumerated()), id: \.element.id) { index, line in
                    if index > 0 { Divider() }
                    lineRow(line)
                }
            }
            .dsCard(padding: nil)
        }
    }

    /// A word of the session: its status, and a click (or Space) opens it in
    /// the notebook.
    private func lineRow(_ line: StudySummary.Line) -> some View {
        let word = store.word(withID: line.id)
        return Button {
            WordNotebook.open(on: line.id) { openWindow(id: $0) }
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                Text(line.term).font(DS.Typography.callout.weight(.medium))
                if let meaning = word.flatMap(SavedWordRow.oneLineMeaning(of:)) {
                    Text(MarkdownUtils.sanitizeLLMOutput(meaning))
                        .font(DS.Typography.callout)
                        .foregroundStyle(DS.Color.textSecondary)
                }
                Spacer(minLength: DS.Spacing.sm)
                if let word {
                    WordStatusBadge(status: WordStatus.of(word))
                }
            }
            .lineLimit(1)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .contentShape(Rectangle())
            .background(focusedLine == line.id ? DS.Color.accentSubtle : .clear)
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($focusedLine, equals: line.id)
        .help("Open in the notebook")
    }

    static func durationText(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .short
        formatter.allowedUnits = seconds < 60 ? [.second] : [.minute]
        formatter.maximumUnitCount = 1
        return formatter.string(from: max(1, seconds)) ?? ""
    }
}
