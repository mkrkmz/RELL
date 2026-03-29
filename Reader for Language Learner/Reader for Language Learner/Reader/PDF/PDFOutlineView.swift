//
//  PDFOutlineView.swift
//  Reader for Language Learner
//
//  Renders the PDF document's table of contents (outline/bookmarks).
//  • Root items start expanded; nested items start collapsed (lazy).
//  • Toolbar provides Expand All / Collapse All.
//

import PDFKit
import SwiftUI

// MARK: - PDFOutlineView

struct PDFOutlineView: View {
    var pdfViewManager: PDFViewManager

    /// Drives a full rebuild of the tree so all items reset to the new default.
    @State private var rebuildKey     = UUID()
    /// nil = depth-based default, true = all expanded, false = all collapsed.
    @State private var defaultExpanded: Bool? = nil

    private var outlineRoot: PDFOutline? {
        pdfViewManager.pdfView?.document?.outlineRoot
    }

    var body: some View {
        Group {
            if let root = outlineRoot, root.numberOfChildren > 0 {
                VStack(spacing: 0) {
                    toolbar
                    Divider()
                    outlineTree(root: root)
                }
            } else {
                emptyState
            }
        }
        .id(pdfViewManager.pdfView?.document)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: DS.Spacing.xs) {
            Spacer()
            Button {
                defaultExpanded = true
                rebuildKey = UUID()
            } label: {
                Label("Expand All", systemImage: "chevron.down.2")
                    .font(DS.Typography.caption2)
                    .labelStyle(.iconOnly)
            }
            .help("Expand All")
            .buttonStyle(.plain)
            .foregroundStyle(DS.Color.textSecondary)

            Button {
                defaultExpanded = false
                rebuildKey = UUID()
            } label: {
                Label("Collapse All", systemImage: "chevron.up.2")
                    .font(DS.Typography.caption2)
                    .labelStyle(.iconOnly)
            }
            .help("Collapse All")
            .buttonStyle(.plain)
            .foregroundStyle(DS.Color.textSecondary)
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xs)
    }

    // MARK: - Tree

    private func outlineTree(root: PDFOutline) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<root.numberOfChildren, id: \.self) { i in
                    if let child = root.child(at: i) {
                        PDFOutlineItemView(
                            outline: child,
                            depth: 0,
                            pdfView: pdfViewManager.pdfView,
                            defaultExpanded: defaultExpanded
                        )
                    }
                }
            }
            .padding(.vertical, DS.Spacing.xs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .id(rebuildKey)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.md) {
            Spacer()
            Image(systemName: "list.bullet.indent")
                .font(.system(size: 32, weight: .ultraLight))
                .foregroundStyle(DS.Color.textTertiary)
            VStack(spacing: DS.Spacing.xs) {
                Text("No Outline")
                    .font(DS.Typography.headline)
                    .foregroundStyle(DS.Color.textSecondary)
                Text("This PDF has no table of contents.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, DS.Spacing.xl)
    }
}

// MARK: - Outline Item Row

struct PDFOutlineItemView: View {
    let outline: PDFOutline
    let depth: Int
    weak var pdfView: PDFView?

    /// nil = depth-based default (root expanded, children collapsed).
    let defaultExpanded: Bool?

    @State private var isExpanded: Bool
    @State private var isHovered  = false

    init(outline: PDFOutline, depth: Int, pdfView: PDFView?, defaultExpanded: Bool?) {
        self.outline         = outline
        self.depth           = depth
        self.pdfView         = pdfView
        self.defaultExpanded = defaultExpanded
        _isExpanded = State(initialValue: defaultExpanded ?? (depth == 0))
    }

    private var hasChildren: Bool { outline.numberOfChildren > 0 }

    private var pageIndex: Int? {
        guard let dest = outline.destination,
              let page = dest.page,
              let doc  = pdfView?.document
        else { return nil }
        return doc.index(for: page)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            rowButton
            if hasChildren && isExpanded {
                childrenView
            }
        }
    }

    // MARK: - Row

    private var rowButton: some View {
        Button {
            if hasChildren {
                withAnimation(DS.Animation.springFast) { isExpanded.toggle() }
            }
            navigate()
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                // Indent track line for nested items
                if depth > 0 {
                    Color.clear.frame(width: CGFloat(depth - 1) * DS.Spacing.lg)
                    Rectangle()
                        .fill(DS.Color.separator)
                        .frame(width: 1, height: 22)
                        .padding(.trailing, DS.Spacing.xs)
                }

                // Chevron / dot
                Group {
                    if hasChildren {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(DS.Color.textTertiary)
                    } else {
                        Circle()
                            .fill(DS.Color.textTertiary.opacity(0.4))
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(width: 12, alignment: .center)

                // Label
                Text(outline.label ?? "—")
                    .font(depth == 0
                          ? DS.Typography.caption.weight(.medium)
                          : DS.Typography.caption2)
                    .foregroundStyle(depth == 0
                                     ? DS.Color.textPrimary
                                     : DS.Color.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Page number chip
                if let idx = pageIndex {
                    Text("\(idx + 1)")
                        .font(DS.Typography.mono)
                        .foregroundStyle(DS.Color.textTertiary)
                        .padding(.horizontal, DS.Spacing.xs)
                        .padding(.vertical, 1)
                        .background(DS.Color.surfaceElevated)
                        .clipShape(Capsule())
                }
            }
            .padding(.vertical, 5)
            .padding(.leading, DS.Spacing.sm)
            .padding(.trailing, DS.Spacing.sm)
            .background(isHovered ? DS.Color.hoverOverlay : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    // MARK: - Children

    private var childrenView: some View {
        ForEach(0..<outline.numberOfChildren, id: \.self) { i in
            if let child = outline.child(at: i) {
                PDFOutlineItemView(
                    outline: child,
                    depth: depth + 1,
                    pdfView: pdfView,
                    defaultExpanded: defaultExpanded
                )
            }
        }
    }

    // MARK: - Navigation

    private func navigate() {
        guard let dest = outline.destination,
              let page = dest.page
        else { return }
        pdfView?.go(to: page)
    }
}
