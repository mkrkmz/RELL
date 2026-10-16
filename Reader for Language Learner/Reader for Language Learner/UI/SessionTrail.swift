//
//  SessionTrail.swift
//  Reader for Language Learner
//
//  The study session's trail (v18 S5, approved mockup): a slice per card,
//  each answered one in its rating's colour, the current one marked, the
//  rest waiting. It doubles as the progress bar. Its meaning never rests on
//  colour alone: each slice's help and VoiceOver say the answers, and the
//  summary writes the counts.
//

import SwiftUI

struct SessionTrail: View {
    let ratings: [ReviewRating]
    let total: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<max(total, ratings.count), id: \.self) { index in
                Capsule()
                    .fill(fill(at: index))
                    .frame(maxWidth: .infinity)
                    .frame(height: 8)
                    .help(index < ratings.count ? Text(ratings[index].localizedTitle) : Text(""))
            }
        }
        .animation(DS.Animation.respecting(DS.Animation.springFast, reduceMotion: reduceMotion), value: ratings.count)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Session"))
        .accessibilityValue(Text(Self.spokenSummary(ratings, total: total)))
    }

    private func fill(at index: Int) -> Color {
        if index < ratings.count { return ratings[index].tint }
        if index == ratings.count { return DS.Color.textPrimary.opacity(0.35) }
        return DS.Color.hairlineStrong
    }

    /// "8 of 20 · 6 remembered · 2 again".
    static func spokenSummary(_ ratings: [ReviewRating], total: Int) -> String {
        let again = ratings.filter { $0 == .again }.count
        return String(localized: "\(ratings.count) of \(total) · \(ratings.count - again) remembered · \(again) again")
    }

    /// Answers in a row, from the latest back, that weren't "Again".
    static func combo(_ ratings: [ReviewRating]) -> Int {
        ratings.reversed().prefix { $0 != .again }.count
    }
}
