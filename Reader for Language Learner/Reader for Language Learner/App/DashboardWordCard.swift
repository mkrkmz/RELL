//
//  DashboardWordCard.swift
//  Reader for Language Learner
//
//  Inline review card on the dashboard: shows one due word at a time as a
//  flip card with Again/Good/Easy ratings, using the same SRS as QuizView
//  (SavedWordsStore.applyReview). Replaces the static review prompt row.
//

import SwiftUI

struct DashboardWordCard: View {
    var store: SavedWordsStore
    var onReviewAll: (() -> Void)?

    @State private var isFlipped = false
    @State private var reviewedThisVisit = 0

    private var dueWords: [SavedWord] {
        guard store.pendingReviewCount > 0 else { return [] }
        return store.reviewQueue(includeAll: false)
    }

    private var currentWord: SavedWord? {
        dueWords.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if let word = currentWord {
                flipCard(for: word)

                if isFlipped {
                    ratingRow(for: word)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            } else {
                caughtUpRow
            }
        }
        .background(DS.Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .strokeBorder(DS.Color.separator.opacity(0.3), lineWidth: 1)
        )
        .animation(DS.Animation.standard, value: isFlipped)
        .animation(DS.Animation.standard, value: currentWord?.id)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DS.Spacing.sm) {
            if !dueWords.isEmpty {
                Circle()
                    .fill(DS.Color.warning)
                    .frame(width: 6, height: 6)
            }

            Text(headerText)
                .font(DS.Typography.caption.weight(.semibold))
                .foregroundStyle(DS.Color.textSecondary)

            Spacer(minLength: DS.Spacing.md)

            if let onReviewAll {
                Button("Review all", action: onReviewAll)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .font(DS.Typography.caption)
                    .help("Open the full review session")
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.md)
        .padding(.bottom, DS.Spacing.sm)
    }

    private var headerText: String {
        let count = dueWords.count
        if count == 0 { return "Review" }
        return count == 1 ? "1 word to review" : "\(count) words to review"
    }

    // MARK: - Flip Card

    private func flipCard(for word: SavedWord) -> some View {
        Button {
            isFlipped.toggle()
        } label: {
            ZStack {
                cardFace(front: true, word: word)
                    .opacity(isFlipped ? 0 : 1)
                    .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))

                cardFace(front: false, word: word)
                    .opacity(isFlipped ? 1 : 0)
                    .rotation3DEffect(.degrees(isFlipped ? 0 : -180), axis: (x: 0, y: 1, z: 0))
            }
            .frame(maxWidth: .infinity, minHeight: 96)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.bottom, isFlipped ? DS.Spacing.sm : DS.Spacing.lg)
        .accessibilityLabel(
            isFlipped
            ? "Definition: \(word.reviewDefinition)"
            : "Review card: \(word.term)"
        )
        .accessibilityHint(isFlipped ? "Rate your recall below" : "Click to reveal the definition")
    }

    @ViewBuilder
    private func cardFace(front: Bool, word: SavedWord) -> some View {
        Group {
            if front {
                VStack(spacing: DS.Spacing.xs) {
                    Text(word.term)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(DS.Color.textPrimary)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.7)
                        .lineLimit(2)
                    Text("Click to reveal")
                        .font(DS.Typography.caption2)
                        .foregroundStyle(DS.Color.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(word.term)
                        .font(DS.Typography.caption.weight(.semibold))
                        .foregroundStyle(DS.Color.textTertiary)
                    Text(word.reviewDefinition)
                        .font(DS.Typography.callout)
                        .foregroundStyle(DS.Color.textPrimary)
                        .lineSpacing(3)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, minHeight: 96)
        .background(DS.Color.surfaceInset.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
    }

    // MARK: - Rating

    private func ratingRow(for word: SavedWord) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            ratingButton(.again, color: DS.Color.warning, for: word)
            ratingButton(.good, color: DS.Color.accent, for: word)
            ratingButton(.easy, color: DS.Color.success, for: word)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.bottom, DS.Spacing.md)
    }

    private func ratingButton(_ rating: ReviewRating, color: Color, for word: SavedWord) -> some View {
        Button {
            _ = store.applyReview(rating, to: word)
            reviewedThisVisit += 1
            isFlipped = false
        } label: {
            Label(rating.label, systemImage: rating.icon)
                .font(DS.Typography.caption.weight(.semibold))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.sm)
                .background(color.opacity(0.09))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
        }
        .buttonStyle(.plain)
        .help("Mark as \(rating.label) and continue")
        .accessibilityHint("Marks \(word.term) as \(rating.label) and shows the next due word")
    }

    // MARK: - Caught Up

    private var caughtUpRow: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(DS.Color.success)

            Text(caughtUpText)
                .font(DS.Typography.label)
                .foregroundStyle(DS.Color.textPrimary)

            if let nextDueText {
                Text("·  next \(nextDueText)")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.bottom, DS.Spacing.md)
        .accessibilityElement(children: .combine)
    }

    private var caughtUpText: String {
        reviewedThisVisit > 0 ? "All caught up — nice work" : "All caught up"
    }

    /// Relative time of the next scheduled review, if any.
    private var nextDueText: String? {
        let now = Date()
        guard let next = store.words
            .compactMap(\.nextReviewAt)
            .filter({ $0 > now })
            .min()
        else { return nil }
        return Self.relativeFormatter.localizedString(for: next, relativeTo: now)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}
