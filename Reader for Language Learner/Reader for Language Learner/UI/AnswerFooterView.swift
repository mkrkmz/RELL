//
//  AnswerFooterView.swift
//  Reader for Language Learner
//
//  The one line under an Inspector answer (Roadmap v17 Sprint 2): engine ·
//  model · first word · total, and an orange tag when it was slow, with
//  "Why?" opening Settings ▸ AI ▸ Speed. One line at a fixed height — it
//  sits below the result's scroll view and must never grow the column.
//

import SwiftUI

struct AnswerFooterView: View {
    let footer: AnswerFooter
    var onExplain: () -> Void

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
            Text(summary)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(0)
            if let tag {
                Text(tag)
                    .fontWeight(.semibold)
                    .foregroundStyle(DS.Color.warning)
                    .lineLimit(1)
                    .padding(.horizontal, DS.Spacing.xs)
                    .background(DS.Color.warning.opacity(0.12), in: Capsule())
                    .layoutPriority(1)
                Button("Why?", action: onExplain)
                    .buttonStyle(.link)
                    .help("Open Settings ▸ AI ▸ Speed")
                    .layoutPriority(1)
            }
            Spacer(minLength: 0)
        }
        .font(DS.Typography.caption2)
        .foregroundStyle(DS.Color.textTertiary)
        .monospacedDigit()
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.surfaceElevated)
        .overlay(alignment: .top) { Divider() }
        .help(fullText)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(fullText)
    }

    private var dotColor: Color {
        if footer.isCached { return DS.Color.textTertiary }
        switch footer.engine {
        case .apple:    return DS.Color.accent
        case .provider: return DS.Color.success
        }
    }

    private var engineText: [String] {
        switch footer.engine {
        case .apple:
            return [String(localized: "Apple")]
        case .provider(let name, let model):
            return [name, model.map { $0.components(separatedBy: "/").last ?? $0 }].compactMap { $0 }
        }
    }

    private var summary: String {
        var parts: [String] = []
        if footer.isCached { parts.append(String(localized: "Saved answer")) }
        parts += engineText
        if footer.isCached {
            parts.append(String(localized: "refresh for a new one"))
        } else {
            if let first = footer.firstToken, footer.flag == nil {
                parts.append(String(localized: "first word \(AnswerFooter.seconds(first))"))
            }
            if let total = footer.total {
                parts.append(String(localized: "total \(AnswerFooter.seconds(total))"))
            }
        }
        return parts.joined(separator: " · ")
    }

    private var tag: String? {
        switch footer.flag {
        case .waited(let seconds):     return String(localized: "waited \(AnswerFooter.seconds(seconds)) in line")
        case .modelLoaded(let seconds): return String(localized: "model loaded · \(AnswerFooter.seconds(seconds))")
        case .slowCloud(let seconds):  return String(localized: "cloud slow to start · \(AnswerFooter.seconds(seconds))")
        case nil:                      return nil
        }
    }

    private var fullText: String {
        [summary, tag].compactMap { $0 }.joined(separator: " · ")
    }
}
