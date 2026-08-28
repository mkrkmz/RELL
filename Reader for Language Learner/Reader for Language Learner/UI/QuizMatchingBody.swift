//
//  QuizMatchingBody.swift
//  Reader for Language Learner
//
//  The matching game's grid (Roadmap v11 Sprint 2). Two columns — terms on
//  the left, their definitions on the right, shuffled apart — paired up by
//  clicking one from each side.
//
//  Kept in its own file rather than as a fifth branch inside `QuizView`: the
//  other modes ask about one card at a time and share its frame, while this
//  one runs a whole round and needs none of it.
//

import SwiftUI

struct QuizMatchingBody: View {

    /// One round's worth of words, already chosen by the caller.
    let words: [SavedWord]
    /// Position of this round in the run, for the header.
    let roundPosition: Int
    let roundTotal: Int
    let isCram: Bool
    /// A pair was matched (`true`) or a wrong guess made (`false`) — the run's
    /// accuracy is tallied from these.
    let onAttempt: (Bool) -> Void
    /// Every pair is matched; move on to the next round.
    let onRoundComplete: () -> Void

    @State private var round: MatchingRound?
    /// The cell that just refused a pairing, for the shake.
    @State private var rejectedCardID: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: DS.Spacing.lg) {
            header

            if let round {
                grid(round)
            } else {
                // The caller hides the mode in this case; this is the belt to
                // that braces.
                DSEmptyState(
                    icon: "square.grid.2x2",
                    title: "Not enough pairs",
                    message: "Save a few more words with definitions to play a round."
                )
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, DS.Spacing.md)
        .onAppear { buildRound() }
        .onChange(of: words.map(\.id)) { _, _ in buildRound() }
        .onExitCommand { round?.clearSelection() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: DS.Spacing.xs) {
            ProgressView(
                value: Double(round?.matchedWordIDs.count ?? 0),
                total: Double(max(1, round?.pairCount ?? 1))
            )
            .tint(DS.Color.accent)

            HStack {
                Text("Round \(roundPosition) of \(roundTotal)")
                Spacer()
                if isCram {
                    Label("Cram", systemImage: "bolt.fill")
                        .foregroundStyle(DS.Color.warning)
                }
                // Said plainly, because it's a real difference from the other
                // modes rather than a detail: this one is practice.
                Label("Practice only", systemImage: "gamecontroller")
                    .foregroundStyle(DS.Color.textTertiary)
            }
            .font(DS.Typography.caption2.weight(.semibold))
            .foregroundStyle(DS.Color.textTertiary)
        }
        .padding(.horizontal, DS.Spacing.md)
    }

    // MARK: - Grid

    private func grid(_ round: MatchingRound) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.md) {
            column(round.terms, isTerm: true, round: round)
            column(round.answers, isTerm: false, round: round)
        }
        .padding(.horizontal, DS.Spacing.md)
    }

    private func column(_ cards: [MatchingRound.Card], isTerm: Bool, round: MatchingRound) -> some View {
        VStack(spacing: DS.Spacing.sm) {
            ForEach(cards) { card in
                cell(card, isTerm: isTerm, round: round)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func cell(_ card: MatchingRound.Card, isTerm: Bool, round: MatchingRound) -> some View {
        let matched = round.isMatched(card)
        let selected = isTerm ? round.selectedTermID == card.id : round.selectedAnswerID == card.id

        return Button {
            select(card, isTerm: isTerm)
        } label: {
            Text(card.text)
                .font(isTerm ? DS.Typography.headline : DS.Typography.caption)
                .foregroundStyle(matched ? DS.Color.textTertiary : DS.Color.textPrimary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(isTerm ? 1 : 4)
                .padding(DS.Spacing.sm)
                .background(background(matched: matched, selected: selected))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                        .strokeBorder(
                            selected ? DS.Color.accent : DS.Color.hairlineStrong,
                            lineWidth: selected ? 1.5 : 0.7
                        )
                )
                .opacity(matched ? 0.5 : 1)
                .offset(x: shakeOffset(for: card))
        }
        .buttonStyle(.plain)
        .disabled(matched)
        .animation(DS.Animation.springFast, value: selected)
        .animation(DS.Animation.springFast, value: matched)
        .animation(DS.Animation.fast, value: rejectedCardID)
        .accessibilityLabel(card.text)
        .accessibilityValue(matched ? Text("Matched") : selected ? Text("Selected") : Text("Not matched"))
        .accessibilityHint(isTerm ? Text("Pick this word, then its meaning") : Text("Pick this meaning, then its word"))
    }

    private func background(matched: Bool, selected: Bool) -> some ShapeStyle {
        if matched { return AnyShapeStyle(DS.Color.success.opacity(0.14)) }
        if selected { return AnyShapeStyle(DS.Color.accentSubtle) }
        return AnyShapeStyle(DS.Color.surfaceElevated)
    }

    private func shakeOffset(for card: MatchingRound.Card) -> CGFloat {
        guard !reduceMotion, rejectedCardID == card.id else { return 0 }
        return 6
    }

    // MARK: - Play

    private func buildRound() {
        round = MatchingRound(words: words, answer: { $0.usableDefinition })
        rejectedCardID = nil
    }

    private func select(_ card: MatchingRound.Card, isTerm: Bool) {
        guard var current = round else { return }
        let outcome = isTerm ? current.selectTerm(card.id) : current.selectAnswer(card.id)
        round = current

        switch outcome {
        case .pending:
            break
        case .matched:
            onAttempt(true)
            if current.isComplete {
                // Let the last pair land before the grid is replaced.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { onRoundComplete() }
            }
        case .wrong:
            onAttempt(false)
            rejectedCardID = card.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                if rejectedCardID == card.id { rejectedCardID = nil }
            }
        }
    }
}
