//
//  ZenModeBar.swift
//  Reader for Language Learner
//
//  The only chrome shown in zen mode: a slim strip at the top of the reader
//  that stays out of the way until the pointer approaches, then reveals a
//  minimal glass bar with the document title, reading position, and an exit
//  control. Keeps immersive reading immersive while leaving a way back.
//

import SwiftUI

struct ZenModeBar: View {
    let title: String
    let subtitle: String
    let onExit: () -> Void

    @State private var revealed = false

    var body: some View {
        Group {
            if revealed {
                bar
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else {
                // Slim invisible hover-catch — approach the top edge to reveal.
                Color.clear
                    .frame(height: 6)
                    .contentShape(Rectangle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .onHover { hovering in
            withAnimation(DS.Animation.standard) { revealed = hovering }
        }
    }

    private var bar: some View {
        HStack(spacing: DS.Spacing.md) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(DS.Typography.headline)
                    .lineLimit(1)
                    .foregroundStyle(DS.Color.textPrimary)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: DS.Spacing.md)

            Button(action: onExit) {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(DS.Typography.icon(15, weight: .medium))
                    .foregroundStyle(DS.Color.textPrimary)
                    .padding(DS.Spacing.xs)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Exit Zen Mode")
            .accessibilityLabel("Exit Zen Mode")
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
        .frame(maxWidth: .infinity)
        .dsGlassCard(radius: 0, fallback: AnyShapeStyle(.regularMaterial), fallbackShadow: DS.Shadow.float)
    }
}
