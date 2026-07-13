//
//  TagEditorView.swift
//  Reader for Language Learner
//
//  Reusable tag (deck) chips, a wrapping flow layout, and an inline editor
//  used in the saved-word detail sheet.
//

import SwiftUI

// MARK: - Flow Layout

/// Left-aligned wrapping layout for chips of varying width.
struct FlowLayout: Layout {
    var spacing: CGFloat = DS.Spacing.xs

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                totalWidth = max(totalWidth, rowWidth - spacing)
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth - spacing)
        return CGSize(width: min(totalWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Tag Chip

struct TagChip: View {
    let tag: String
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: DS.Spacing.xxs) {
            Image(systemName: "tag.fill")
                .font(DS.Typography.icon(8))
                .foregroundStyle(DS.Color.accent.opacity(0.8))
            Text(tag)
                .font(DS.Typography.caption2.weight(.medium))
                .foregroundStyle(DS.Color.textSecondary)
                .lineLimit(1)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(DS.Typography.icon(7, weight: .bold))
                        .foregroundStyle(DS.Color.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DS.Spacing.xs)
        .padding(.vertical, 2)
        .background(DS.Color.accentSubtle)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(DS.Color.accentMuted.opacity(0.4), lineWidth: 0.5))
    }
}

// MARK: - Tag Editor

struct TagEditorView: View {
    @Binding var tags: [String]
    var suggestions: [String] = []

    @State private var newTag = ""

    private var trimmedNew: String {
        newTag.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var unusedSuggestions: [String] {
        suggestions.filter { suggestion in
            !tags.contains { $0.lowercased() == suggestion.lowercased() }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            if !tags.isEmpty {
                FlowLayout {
                    ForEach(tags, id: \.self) { tag in
                        TagChip(tag: tag, onRemove: { remove(tag) })
                    }
                }
            }

            HStack(spacing: DS.Spacing.xs) {
                TextField("Add tag", text: $newTag)
                    .textFieldStyle(.roundedBorder)
                    .font(DS.Typography.caption)
                    .onSubmit { commit() }
                Button("Add", action: commit)
                    .controlSize(.small)
                    .disabled(trimmedNew.isEmpty)
            }

            if !unusedSuggestions.isEmpty {
                FlowLayout {
                    ForEach(unusedSuggestions, id: \.self) { suggestion in
                        Button { add(suggestion) } label: {
                            TagChip(tag: suggestion)
                                .opacity(0.7)
                        }
                        .buttonStyle(.plain)
                        .help("Add existing tag")
                    }
                }
            }
        }
    }

    private func commit() {
        for token in trimmedNew.split(whereSeparator: \.isWhitespace).map(String.init) {
            add(token)
        }
        newTag = ""
    }

    private func add(_ tag: String) {
        let clean = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty,
              !tags.contains(where: { $0.lowercased() == clean.lowercased() }) else { return }
        tags.append(clean)
    }

    private func remove(_ tag: String) {
        tags.removeAll { $0.lowercased() == tag.lowercased() }
    }
}
