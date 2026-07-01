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
    var prefersStreamingRenderer: Bool = false
    var showsContextBreakout: Bool = false

    var body: some View {
        if showsContextBreakout {
            // Render straight into the context cards — even while streaming —
            // so the layout doesn't reshuffle the moment the stream ends.
            ContextAwareResultView(content: content, isStreaming: prefersStreamingRenderer)
        } else if prefersStreamingRenderer {
            StreamingResultView(content: content)
        } else {
            renderedContent
        }
    }

    @ViewBuilder
    private var renderedContent: some View {
        switch module {
        case .collocations:
            CollocationResultView(content: content)
        case .examplesEN:
            ExamplesResultView(content: content)
        case .pronunciationEN:
            PronunciationResultView(content: content)
        case .usageNotesEN:
            UsageNotesResultView(content: content)
        case .synonymsEN, .wordFamilyEN:
            LineListResultView(content: content, emphasizeDivider: true)
        default:
            AttributedResultView(content: content)
        }
    }
}

struct ContextAwareResultView: View {
    let content: String
    /// While the stream is live we show the first card immediately (with just
    /// one paragraph) instead of falling back to inline text, so the "In This
    /// Context" box is visible from the first tokens and the "General Meaning"
    /// box slides in once the model emits the paragraph break.
    var isStreaming: Bool = false

    private var paragraphs: [String] {
        content
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        Group {
            if paragraphs.count >= 2 {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    contextBreakoutCard(
                        title: "In This Context",
                        body: paragraphs.first ?? "",
                        tint: DS.Color.accentStrong
                    )

                    contextBreakoutCard(
                        title: "General Meaning",
                        body: paragraphs.dropFirst().joined(separator: "\n\n"),
                        tint: DS.Color.textSecondary
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            } else if isStreaming, let first = paragraphs.first {
                contextBreakoutCard(
                    title: "In This Context",
                    body: first,
                    tint: DS.Color.accentStrong
                )
            } else {
                AttributedResultView(content: content)
            }
        }
        .animation(DS.Animation.standard, value: paragraphs.count)
    }

    func contextBreakoutCard(title: String, body: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(title.uppercased())
                .font(DS.Typography.caption2.weight(.bold))
                .foregroundStyle(tint)

            Text(body)
                .font(DS.Typography.body)
                .foregroundStyle(DS.Color.textPrimary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DS.Spacing.lg)
        .background(DS.Color.panel)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .strokeBorder(tint.opacity(0.18), lineWidth: 0.8)
        )
    }
}

/// Animated "still generating" indicator shown at the tail of a streaming
/// result. The waving dots keep moving even when the model pauses mid-stream
/// (e.g. while it silently reasons), so the output never looks finished when
/// it isn't.
struct StreamingActivityIndicator: View {
    var label: String = "Generating…"
    @State private var animating = false

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(DS.Color.accent)
                        .frame(width: 6, height: 6)
                        .scaleEffect(animating ? 1.0 : 0.5)
                        .opacity(animating ? 1.0 : 0.3)
                        .animation(
                            .easeInOut(duration: 0.55)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.18),
                            value: animating
                        )
                }
            }

            Text(label)
                .font(DS.Typography.caption2.weight(.medium))
                .foregroundStyle(DS.Color.textTertiary)
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xs)
        .background(DS.Color.cardSoft)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(DS.Color.hairline, lineWidth: 0.5)
        )
        .accessibilityLabel("Generating response")
        .onAppear { animating = true }
    }
}

struct StreamingResultView: View {
    let content: String

    var body: some View {
        Text(content)
            .font(DS.Typography.body)
            .foregroundStyle(DS.Color.textPrimary)
            .textSelection(.enabled)
            .lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Spacing.lg)
        .background(DS.Color.panel)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        .frame(maxWidth: .infinity, alignment: .leading)
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
            .fixedSize(horizontal: false, vertical: true)
            .padding(DS.Spacing.lg)
            .background(DS.Color.panel)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LineListResultView: View {
    let content: String
    var emphasizeDivider: Bool = false

    private var lines: [String] {
        content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        if lines.isEmpty {
            AttributedResultView(content: content)
        } else {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    HStack(alignment: .top, spacing: DS.Spacing.sm) {
                        Circle()
                            .fill(DS.Color.accent.opacity(0.75))
                            .frame(width: 6, height: 6)
                            .padding(.top, 7)

                        Text(line)
                            .font(DS.Typography.body)
                            .foregroundStyle(DS.Color.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if emphasizeDivider && index < lines.count - 1 {
                        Divider()
                            .padding(.leading, 14)
                    }
                }
            }
            .padding(DS.Spacing.lg)
            .background(DS.Color.panel)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        }
    }
}

struct ExamplesResultView: View {
    let content: String

    private var examples: [String] {
        content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        if examples.isEmpty {
            AttributedResultView(content: content)
        } else {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                ForEach(Array(examples.enumerated()), id: \.offset) { index, example in
                    HStack(alignment: .top, spacing: DS.Spacing.sm) {
                        Text("\(index + 1)")
                            .font(DS.Typography.mono.weight(.bold))
                            .foregroundStyle(DS.Color.accent)
                            .frame(width: 20, alignment: .leading)

                        Text(example)
                            .font(DS.Typography.body)
                            .foregroundStyle(DS.Color.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(DS.Spacing.md)
                    .background(DS.Color.panel)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                }
            }
        }
    }
}

struct PronunciationResultView: View {
    let content: String

    private var lines: [String] {
        content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        if lines.isEmpty {
            AttributedResultView(content: content)
        } else {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "waveform")
                            .foregroundStyle(.orange)
                        Text(line)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(DS.Color.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(DS.Spacing.md)
                    .background(DS.Color.panel)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                }
            }
        }
    }
}

struct UsageNotesResultView: View {
    let content: String

    private var rows: [UsageNoteRow] {
        ParsedResultCache.usageNoteRows(for: content)
    }

    var body: some View {
        if rows.isEmpty {
            AttributedResultView(content: content)
        } else {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: DS.Spacing.md) {
                        Text(row.label)
                            .font(DS.Typography.caption.weight(.bold))
                            .foregroundStyle(DS.Color.accentStrong)
                            .padding(.horizontal, DS.Spacing.sm)
                            .padding(.vertical, DS.Spacing.xs)
                            .background(DS.Color.accentSubtle)
                            .clipShape(Capsule())
                            .frame(width: 96, alignment: .leading)

                        Text(row.value)
                            .font(DS.Typography.body)
                            .foregroundStyle(DS.Color.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(DS.Spacing.md)
                    .background(DS.Color.panel)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                }
            }
        }
    }
}

// MARK: - CollocationResultView

/// Parses collocation output and renders each entry as a card.
/// Falls back to `AttributedResultView` when parsing yields no entries.
struct CollocationResultView: View {
    let content: String

    private var entries: [CollocationEntry] {
        ParsedResultCache.collocationEntries(for: content)
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
            .padding(DS.Spacing.sm)
            .background(DS.Color.panel)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
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
                .strokeBorder(DS.Color.hairline, lineWidth: 0.5)
        )
    }
}
