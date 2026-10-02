//
//  ReadingLoopTour.swift
//  Reader for Language Learner
//
//  The reading loop in four pages — select, understand, save, review — with
//  a small picture of each (v14 S4). The last pages of the first-run
//  onboarding, and on its own from Help ▸ Reading Tour.
//

import SwiftUI

enum ReadingLoopTour {
    static let pageCount = 4
}

/// One page of the tour.
struct ReadingLoopTourPage: View {
    let index: Int

    var body: some View {
        VStack(spacing: DS.Spacing.lg) {
            Text(stepLabel)
                .dsOverlineLabel()
                .textCase(.uppercase)
                .foregroundStyle(DS.Color.accent)

            illustration
                .frame(maxWidth: 360)
                .frame(height: 150)
                .background(DS.Color.surfaceInset, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg).strokeBorder(DS.Color.hairline, lineWidth: 0.6))
                .accessibilityHidden(true)

            VStack(spacing: DS.Spacing.xs) {
                Text(title)
                    .font(DS.Typography.title)
                    .foregroundStyle(DS.Color.textPrimary)
                Text(detail)
                    .font(DS.Typography.subhead)
                    .foregroundStyle(DS.Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 400)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var stepLabel: LocalizedStringKey {
        switch index {
        case 0: return "1 · Select"
        case 1: return "2 · Understand"
        case 2: return "3 · Save"
        default: return "4 · Review"
        }
    }

    private var title: LocalizedStringKey {
        switch index {
        case 0: return "Select a word"
        case 1: return "Understand it in the Inspector"
        case 2: return "Save it, so you don't lose it"
        default: return "Review it at the right time"
        }
    }

    private var detail: LocalizedStringKey {
        switch index {
        case 0: return "Double-click a word or drag across a sentence. The bar above it offers the first step."
        case 1: return "The word's card gives a short meaning; explanations, grammar and simpler wording are one click away."
        case 2: return "Saved words are underlined in your books, and RELL notes where you meet them again."
        default: return "RELL brings each word back just before you'd forget it. Find today's reviews on the home screen."
        }
    }

    // MARK: Pictures

    @ViewBuilder
    private var illustration: some View {
        switch index {
        case 0:
            VStack(spacing: DS.Spacing.sm) {
                HStack(spacing: DS.Spacing.xs) {
                    pill("Save", prominent: true)
                    pill("Analyze", prominent: false)
                    Image(systemName: "speaker.wave.2").foregroundStyle(DS.Color.textSecondary)
                }
                .padding(DS.Spacing.xxs + 1)
                .background(DS.Color.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(DS.Color.hairline, lineWidth: 0.6))
                // Sample text from a book: not translated.
                HStack(spacing: 0) {
                    Text(verbatim: "…was afraid of meeting his ")
                        .foregroundStyle(DS.Color.textSecondary)
                    Text(verbatim: "landlady")
                        .bold()
                        .foregroundStyle(DS.Color.textPrimary)
                        .background(DS.Color.accentMuted, in: RoundedRectangle(cornerRadius: DS.Radius.xs))
                    Text(verbatim: ".")
                        .foregroundStyle(DS.Color.textSecondary)
                }
                .font(.system(.title3, design: .serif))
            }
        case 1:
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(verbatim: "landlady").font(DS.Typography.wordDisplay)
                Text(verbatim: "ev sahibesi").font(DS.Typography.callout).foregroundStyle(DS.Color.textSecondary)
                HStack(spacing: DS.Spacing.xs) {
                    pill("Define", prominent: false)
                    pill("Examples", prominent: false)
                    pill("More", prominent: false)
                }
            }
            .padding(DS.Spacing.md)
            .background(DS.Gradient.accentWash, in: RoundedRectangle(cornerRadius: DS.Radius.md))
        case 2:
            VStack(spacing: DS.Spacing.sm) {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "star.fill").foregroundStyle(DS.Color.star)
                    Text(verbatim: "landlady")
                        .font(.system(.title3, design: .serif))
                        .underline(color: DS.Color.accent)
                }
                Text("Last met: Crime and Punishment · yesterday")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
            }
        default:
            VStack(spacing: DS.Spacing.xs) {
                Text(verbatim: "12")
                    .font(DS.Typography.largeTitle)
                    .monospacedDigit()
                    .foregroundStyle(DS.Color.textPrimary)
                Text("words due for review today")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textSecondary)
                pill("Start Review", prominent: true)
            }
        }
    }

    private func pill(_ title: LocalizedStringKey, prominent: Bool) -> some View {
        Text(title)
            .font(DS.Typography.caption.weight(.semibold))
            .foregroundStyle(prominent ? SwiftUI.Color.white : DS.Color.accent)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, 3)
            .background(prominent ? DS.Color.accent : DS.Color.accentSubtle, in: Capsule())
    }
}

/// The tour on its own (Help ▸ Reading Tour).
struct ReadingLoopTourSheet: View {
    let onDone: () -> Void
    @State private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            ReadingLoopTourPage(index: page)
                .id(page)
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, DS.Spacing.xxl)
                .padding(.top, DS.Spacing.xxl)

            HStack(spacing: DS.Spacing.md) {
                Button("Skip", action: onDone)
                    .buttonStyle(.borderless)
                    .foregroundStyle(DS.Color.textTertiary)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                ReadingLoopTourDots(current: page, count: ReadingLoopTour.pageCount)
                Spacer()
                if page > 0 {
                    Button("Back") { withAnimation(DS.Animation.standard) { page -= 1 } }
                        .buttonStyle(.bordered)
                }
                if page < ReadingLoopTour.pageCount - 1 {
                    Button("Next") { withAnimation(DS.Animation.standard) { page += 1 } }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Done", action: onDone)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(DS.Spacing.lg)
            .background(DS.Color.surfaceElevated.opacity(0.6))
        }
        .frame(width: 560, height: 500)
        .background(DS.Color.surface)
    }
}

struct ReadingLoopTourDots: View {
    let current: Int
    let count: Int

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == current ? DS.Color.accent : DS.Color.hairlineStrong)
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Page \(current + 1) of \(count)"))
    }
}
