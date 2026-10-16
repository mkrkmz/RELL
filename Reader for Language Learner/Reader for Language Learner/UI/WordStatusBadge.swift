//
//  WordStatusBadge.swift
//  Reader for Language Learner
//
//  A word's status as a tinted capsule with its mark and word (v18 S5).
//

import SwiftUI

struct WordStatusBadge: View {
    let status: WordStatus

    var body: some View {
        Label {
            Text(status.title())
        } icon: {
            Image(systemName: status.symbol)
                .imageScale(.small)
        }
        .labelStyle(WordStatusLabelStyle())
        .font(DS.Typography.caption2.weight(.semibold))
        .foregroundStyle(status.color)
        .padding(.horizontal, DS.Spacing.xs)
        .padding(.vertical, DS.Spacing.hairline)
        .background(status.color.opacity(0.12), in: Capsule())
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.title())
    }
}

private struct WordStatusLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: DS.Spacing.xxs) {
            configuration.icon
            configuration.title
        }
    }
}
