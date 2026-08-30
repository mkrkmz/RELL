//
//  QuizResultView.swift
//  Reader for Language Learner
//
//  What a review run ends on: the streak banner, the tallies, and where to
//  go next. Split out of `QuizView` (Roadmap v11 Sprint 1) — it shares the
//  session and the store with the card modes and nothing else.
//

import SwiftUI

struct QuizResultView: View {
    let session: QuizSession
    var store: SavedWordsStore
    /// The mode the run was played in — a game reports pairs, not grades.
    let mode: QuizMode
    /// Whether there is anything left to run again.
    let canReviewMore: Bool
    let onReviewMore: () -> Void
    var onContinueReading: (() -> Void)?
    var onOpenSavedWords: (() -> Void)?


    /// Flame + current streak, plus a snowflake count when freezes are banked.
    /// Earned freezes auto-bridge a single missed day (see ReviewStreak).
    @ViewBuilder
    private var reviewStreakBanner: some View {
        let streak = store.reviewStreak()
        if streak.current > 0 {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(DS.Color.warning)
                Text("\(streak.current)-day streak")
                    .font(DS.Typography.subhead.weight(.semibold))
                    .foregroundStyle(DS.Color.textPrimary)

                if streak.freezesRemaining > 0 {
                    Divider().frame(height: 12)
                    HStack(spacing: 2) {
                        Image(systemName: "snowflake")
                            .foregroundStyle(DS.Color.accent)
                        Text("\(streak.freezesRemaining)")
                            .font(DS.Typography.caption.weight(.semibold))
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                    .help("Streak freezes — each automatically covers one missed day")
                }
            }
            .font(DS.Typography.caption)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .dsGlassCapsule(fallbackShadow: nil)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                streak.freezesRemaining > 0
                    ? "\(streak.current) day review streak, \(streak.freezesRemaining) freezes banked"
                    : "\(streak.current) day review streak"
            )
        }
    }


    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: DS.Spacing.lg) {
                Image(systemName: session.againCount == 0 ? "star.fill" : "checkmark.circle.fill")
                    .font(DS.Typography.icon(46, weight: .light))
                    .foregroundStyle(session.againCount == 0 ? DS.Color.star : DS.Color.success)

                VStack(spacing: DS.Spacing.xs) {
                    Text("Review Complete")
                        .font(DS.Typography.headline)
                        .foregroundStyle(DS.Color.textPrimary)
                    Text(resultSummaryText)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                        .multilineTextAlignment(.center)
                }

                reviewStreakBanner

                // The grade tallies are all zero after a game — it never
                // grades — so a round-based mode reports what it did instead.
                if mode.affectsSchedule {
                    HStack(spacing: DS.Spacing.lg) {
                        resultStat(value: "\(session.goodCount)", label: "Good", color: DS.Color.accent)
                        resultStat(value: "\(session.easyCount)", label: "Easy", color: DS.Color.success)
                        resultStat(value: "\(session.againCount)", label: "Again", color: DS.Color.danger)
                    }
                } else {
                    HStack(spacing: DS.Spacing.lg) {
                        resultStat(value: "\(session.correctCount)", label: "Pairs matched", color: DS.Color.success)
                        resultStat(
                            value: "\(max(0, session.gradedCount - session.correctCount))",
                            label: "Mistakes",
                            color: DS.Color.warning
                        )
                    }
                }

                // Only the modes that check the answer themselves can report a
                // real accuracy; flashcards only have the user's own judgement.
                if let accuracy = session.accuracy {
                    resultStat(
                        value: "\(Int((accuracy * 100).rounded()))%",
                        label: "Answered correctly",
                        color: accuracy >= 0.8 ? DS.Color.success : DS.Color.warning
                    )
                    .frame(maxWidth: .infinity)
                }

                VStack(spacing: DS.Spacing.sm) {
                    Button {
                        onReviewMore()
                    } label: {
                        Label(store.pendingReviewCount > 0 ? "Review More" : "Practice Again", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(!canReviewMore)

                    if let onContinueReading {
                        Button(action: onContinueReading) {
                            Label("Continue Reading", systemImage: "book.pages")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }

                    if let onOpenSavedWords {
                        Button(action: onOpenSavedWords) {
                            Label("Open Saved Words", systemImage: "star")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }
                }
                .font(DS.Typography.caption.weight(.semibold))

                Text("\(store.pendingReviewCount) words still due")
                    .font(DS.Typography.caption2)
                    .foregroundStyle(DS.Color.textTertiary)
            }
            .padding(DS.Spacing.lg)
        }
    }

    private var resultSummaryText: String {
        if !mode.affectsSchedule {
            return String(localized: "Practice only — nothing in your review schedule changed.")
        }
        if store.pendingReviewCount > 0 {
            return "Nice pass. There are still due words waiting in the queue."
        }
        if session.againCount > 0 {
            return "Good work. Words marked Again are scheduled back into review soon."
        }
        return "Clean session. Your due queue is clear for now."
    }

    private func resultStat(value: String, label: LocalizedStringKey, color: Color) -> some View {
        VStack(spacing: DS.Spacing.xxs) {
            Text(value)
                .font(DS.Typography.statNumber(32))
                .foregroundStyle(color)
            Text(label)
                .font(DS.Typography.caption2)
                .foregroundStyle(DS.Color.textTertiary)
        }
    }
}
