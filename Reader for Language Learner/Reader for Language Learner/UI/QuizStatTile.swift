//
//  QuizStatTile.swift
//  Reader for Language Learner
//
//  The small tinted figure used by the review surfaces — the queue counts on
//  the start screen and the streak on the results screen. Shared rather than
//  duplicated once `QuizView` was split (Roadmap v11 Sprint 1).
//

import SwiftUI

struct QuizStatTile: View {
    let icon: String
    let value: String
    /// `LocalizedStringKey`, not `String`: `Text(String)` skips the catalog.
    let label: LocalizedStringKey
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Image(systemName: icon)
                .font(DS.Typography.icon(13, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(DS.Typography.headline)
                .foregroundStyle(DS.Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(DS.Typography.caption2)
                .foregroundStyle(DS.Color.textTertiary)
                .lineLimit(1)
        }
        .padding(DS.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
    }
}
