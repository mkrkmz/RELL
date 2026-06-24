//
//  HighlightsView.swift
//  Reader for Language Learner
//
//  Sidebar panel listing user-created highlights for the open document.
//  Tap a row → jump to that page. Swipe → delete. Swatch menu → recolor.
//

import PDFKit
import SwiftUI

struct HighlightsView: View {

    var highlightStore:  PDFHighlightStore
    var pdfViewManager:  PDFViewManager
    var currentFilename: String?

    var body: some View {
        Group {
            if let filename = currentFilename {
                let entries = highlightStore.highlights(for: filename)
                if entries.isEmpty {
                    emptyState
                } else {
                    list(entries: entries)
                }
            } else {
                noDocumentState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - List

    private func list(entries: [PDFHighlight]) -> some View {
        List {
            ForEach(entries) { highlight in
                HighlightRow(
                    highlight: highlight,
                    onRecolor: { highlightStore.updateColor(id: highlight.id, color: $0) }
                )
                .contentShape(Rectangle())
                .onTapGesture { navigate(to: highlight) }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        withAnimation { highlightStore.remove(id: highlight.id) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(
                    top: DS.Spacing.xxs, leading: DS.Spacing.sm,
                    bottom: DS.Spacing.xxs, trailing: DS.Spacing.sm
                ))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Navigation

    private func navigate(to highlight: PDFHighlight) {
        guard let doc = pdfViewManager.pdfView?.document,
              highlight.pageIndex < doc.pageCount,
              let page = doc.page(at: highlight.pageIndex)
        else { return }
        pdfViewManager.pdfView?.go(to: page)
    }

    // MARK: - Empty / No-doc States

    private var emptyState: some View {
        DSEmptyState(
            icon:    "highlighter",
            title:   "No Highlights",
            message: "Select text, right-click, and choose Highlight to mark passages."
        )
    }

    private var noDocumentState: some View {
        DSEmptyState(
            icon:    "doc.text",
            title:   "No Document",
            message: "Open a PDF to start highlighting."
        )
    }
}

// MARK: - HighlightRow

private struct HighlightRow: View {
    let highlight: PDFHighlight
    var onRecolor: (HighlightColor) -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            // Color spine
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(nsColor: highlight.color.nsColor))
                .frame(width: 4)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(highlight.selectedText)
                    .font(DS.Typography.subhead)
                    .foregroundStyle(DS.Color.textPrimary)
                    .lineLimit(2)
                HStack(spacing: DS.Spacing.xs) {
                    Text(highlight.pageLabel)
                        .font(DS.Typography.caption2)
                        .foregroundStyle(DS.Color.textTertiary)
                    Text("·")
                        .font(DS.Typography.caption2)
                        .foregroundStyle(DS.Color.textTertiary)
                    Text(highlight.createdAt, style: .date)
                        .font(DS.Typography.caption2)
                        .foregroundStyle(DS.Color.textTertiary)
                }
            }

            Spacer(minLength: DS.Spacing.xs)

            if isHovered {
                recolorMenu
                    .transition(.opacity)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DS.Color.textTertiary)
            }
        }
        .padding(DS.Spacing.sm)
        .frame(minHeight: 44)
        .background(DS.Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        .onHover { isHovered = $0 }
        .animation(DS.Animation.fast, value: isHovered)
    }

    private var recolorMenu: some View {
        Menu {
            ForEach(HighlightColor.allCases) { color in
                Button {
                    onRecolor(color)
                } label: {
                    Label {
                        Text(color.label)
                    } icon: {
                        Image(systemName: highlight.color == color ? "checkmark.circle.fill" : "circle.fill")
                            .foregroundStyle(Color(nsColor: color.nsColor))
                    }
                }
            }
        } label: {
            Circle()
                .fill(Color(nsColor: highlight.color.nsColor))
                .frame(width: 14, height: 14)
                .overlay(Circle().strokeBorder(DS.Color.separator.opacity(0.5), lineWidth: 0.5))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Change highlight color")
    }
}
