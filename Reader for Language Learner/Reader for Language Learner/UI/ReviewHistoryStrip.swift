//
//  ReviewHistoryStrip.swift
//  Reader for Language Learner
//
//  A word's last answers as marked tiles, oldest first (v18 S5): ↺ – ✓ ✓✓
//  in the rating's colour, so the strip reads without the colour too.
//

import SwiftUI

struct ReviewHistoryStrip: View {
    let events: [ReviewEvent]

    var body: some View {
        HStack(spacing: DS.Spacing.xxs) {
            ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                Text(event.rating.mark)
                    .font(DS.Typography.caption2.weight(.bold))
                    .foregroundStyle(event.rating.tint)
                    .frame(minWidth: 20, minHeight: 20)
                    .padding(.horizontal, event.rating == .easy ? DS.Spacing.xxs : 0)
                    .background(event.rating.tint.opacity(0.13), in: RoundedRectangle(cornerRadius: DS.Radius.xs))
                    .help(Text("\(event.rating.localizedTitle) · \(event.date, format: .dateTime.day().month())"))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Last answers, oldest first"))
        .accessibilityValue(Text(events.map(\.rating.localizedTitle).joined(separator: ", ")))
    }
}
