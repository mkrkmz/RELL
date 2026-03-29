//
//  EmptyStateView.swift
//  Reader for Language Learner
//
//  Extracted from ContentView.swift
//

import SwiftUI

struct EmptyStateView: View {
    let onOpenPDF: () -> Void

    @State private var isHoveringButton = false

    var body: some View {
        ZStack {
            // Subtle radial gradient backdrop
            RadialGradient(
                colors: [DS.Color.accentSubtle, .clear],
                center: .center,
                startRadius: 60,
                endRadius: 320
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Icon badge
                ZStack {
                    Circle()
                        .fill(DS.Color.accentSubtle)
                        .frame(width: 96, height: 96)
                    Circle()
                        .strokeBorder(DS.Color.accentMuted, lineWidth: 1)
                        .frame(width: 96, height: 96)
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 38, weight: .light))
                        .foregroundStyle(DS.Color.accent)
                }
                .dsShadow(DS.Shadow.card)

                Spacer().frame(height: DS.Spacing.xxl)

                // Text block
                VStack(spacing: DS.Spacing.sm) {
                    Text("Open a PDF to start reading")
                        .font(DS.Typography.title)
                        .foregroundStyle(DS.Color.textPrimary)
                    Text("Select a word or sentence while reading\nto look it up instantly with AI.")
                        .font(DS.Typography.subhead)
                        .foregroundStyle(DS.Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }

                Spacer().frame(height: DS.Spacing.xxl)

                // CTA button
                Button(action: onOpenPDF) {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "folder.badge.plus")
                        Text("Open PDF…")
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, DS.Spacing.xl)
                    .padding(.vertical, DS.Spacing.md)
                    .background(DS.Color.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                    .dsShadow(isHoveringButton ? DS.Shadow.float : DS.Shadow.card)
                    .scaleEffect(isHoveringButton ? 1.02 : 1.0)
                    .animation(DS.Animation.springFast, value: isHoveringButton)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("o", modifiers: [.command])
                .onHover { isHoveringButton = $0 }

                Spacer().frame(height: DS.Spacing.lg)

                // Drag hint
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: 11))
                    Text("Or drag a PDF file here")
                        .font(DS.Typography.caption)
                }
                .foregroundStyle(DS.Color.textTertiary)

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
