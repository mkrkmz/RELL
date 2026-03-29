//
//  ResultRenderer.swift
//  Reader for Language Learner
//
//  Routes LLM output to the correct renderer for each module type.
//  - Plain modules  → AttributedResultView  (inline **bold** / *italic* via AttributedString)
//  - Collocations   → CollocationResultView  (parsed cards with structured layout)
//

import SwiftUI

// MARK: - ResultRenderer

struct ResultRenderer: View {
    let content: String
    let module: ModuleType

    var body: some View {
        switch module {
        case .collocations:
            CollocationResultView(content: content)
        default:
            AttributedResultView(content: content)
        }
    }
}

// MARK: - AttributedResultView

/// Renders plain text with optional inline markdown (**bold**, *italic*).
struct AttributedResultView: View {
    let content: String

    private var attributed: AttributedString {
        let opts = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: content, options: opts))
            ?? AttributedString(content)
    }

    var body: some View {
        Text(attributed)
            .font(DS.Typography.body)
            .foregroundStyle(DS.Color.textPrimary)
            .lineSpacing(5)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - CollocationResultView

/// Parses collocation output and renders each entry as a card.
/// Falls back to `AttributedResultView` when parsing yields no entries.
struct CollocationResultView: View {
    let content: String

    private var entries: [CollocationEntry] {
        ResultParser.parseCollocationEntries(content)
    }

    var body: some View {
        if entries.isEmpty {
            AttributedResultView(content: content)
        } else {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                ForEach(entries) { entry in
                    CollocationItemView(entry: entry)
                }
            }
        }
    }
}

// MARK: - CollocationItemView

struct CollocationItemView: View {
    let entry: CollocationEntry

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {

            // ── Header: index · collocation · meaning ────────────────────
            HStack(alignment: .top, spacing: DS.Spacing.xs) {
                Text("\(entry.number).")
                    .font(DS.Typography.mono)
                    .foregroundStyle(DS.Color.accent)
                    .frame(width: 22, alignment: .leading)

                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(entry.collocation)
                        .font(DS.Typography.headline)
                        .foregroundStyle(DS.Color.textPrimary)

                    if !entry.meaning.isEmpty {
                        Text(entry.meaning)
                            .font(DS.Typography.callout)
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                }
            }

            // ── Example + translation ─────────────────────────────────────
            if !entry.exampleEN.isEmpty || !entry.translationTR.isEmpty {
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {

                    if !entry.exampleEN.isEmpty {
                        HStack(alignment: .top, spacing: DS.Spacing.xs) {
                            Image(systemName: "quote.opening")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(DS.Color.accent.opacity(0.55))
                                .padding(.top, 3)
                            Text(entry.exampleEN)
                                .font(DS.Typography.callout)
                                .italic()
                                .foregroundStyle(DS.Color.textSecondary)
                        }
                    }

                    if !entry.translationTR.isEmpty {
                        Text(entry.translationTR)
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Color.textTertiary)
                            .padding(.leading, 18)
                    }
                }
                .padding(.leading, 22)
                .padding(.top, DS.Spacing.xxs)
            }
        }
        .padding(DS.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.sm)
                .strokeBorder(DS.Color.separator.opacity(0.45), lineWidth: 0.5)
        )
    }
}
