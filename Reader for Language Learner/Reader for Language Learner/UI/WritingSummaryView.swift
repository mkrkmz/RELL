//
//  WritingSummaryView.swift
//  Reader for Language Learner
//
//  How a "Write a Sentence" run ended (Roadmap v19 Sprint 3, approved
//  mockup): how many sentences, how many were natural first time, the fix
//  that came up most. No score — the schedule didn't move.
//

import SwiftUI

struct WritingSummaryView: View {
    let session: QuizSession
    let onMore: () -> Void
    let onClose: () -> Void

    var body: some View {
        let writings = session.writings
        let natural = writings.filter { $0.verdict == .natural }.count
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            Label("Practice done", systemImage: "pencil.line")
                .font(DS.Typography.caption.weight(.bold))
                .foregroundStyle(DS.Color.warning)
            Text(writings.count == 1 ? String(localized: "You wrote 1 sentence")
                                     : String(localized: "You wrote \(writings.count) sentences"))
                .font(DS.Typography.largeTitle)

            if !writings.isEmpty {
                HStack(spacing: DS.Spacing.sm) {
                    HStack(spacing: DS.Spacing.xxs) {
                        ForEach(Array(writings.enumerated()), id: \.offset) { _, writing in
                            Circle()
                                .fill(tint(writing.verdict))
                                .frame(width: 10, height: 10)
                        }
                    }
                    .accessibilityHidden(true)
                    Text("\(natural) natural first time · \(writings.count - natural) corrected")
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }

            if let common = SentenceWriting.commonestTopic(writings) {
                Label {
                    Text("Most common fix: \(common.topic) (\(common.count) times)")
                } icon: {
                    Image(systemName: "lightbulb.fill").foregroundStyle(DS.Color.amber)
                }
                .font(DS.Typography.callout)
                .padding(DS.Spacing.sm)
                .background(DS.Color.surfaceInset, in: RoundedRectangle(cornerRadius: DS.Radius.md))
            }

            if session.savedWritings > 0 {
                Text(session.savedWritings == 1 ? String(localized: "1 sentence saved to your notebook.")
                                                : String(localized: "\(session.savedWritings) sentences saved to your notebook."))
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Color.textSecondary)
            }

            Text("Practice: your review schedule stays as it is.")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.textTertiary)

            HStack(spacing: DS.Spacing.sm) {
                Button("More Words", action: onMore)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                Button("Close", action: onClose)
                    .keyboardShortcut(.cancelAction)
                    .help("Esc")
            }
            .controlSize(.large)
        }
        .frame(maxWidth: 520, alignment: .leading)
        .padding(DS.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RadialGradient(colors: [DS.Color.warning.opacity(0.12), .clear], center: .topLeading, startRadius: 0, endRadius: 520)
                .ignoresSafeArea()
        )
    }

    private func tint(_ verdict: SentenceWriting.Verdict) -> Color {
        switch verdict {
        case .natural:    return DS.Color.success
        case .fixed:      return DS.Color.warning
        case .otherSense: return DS.Color.danger
        }
    }
}
