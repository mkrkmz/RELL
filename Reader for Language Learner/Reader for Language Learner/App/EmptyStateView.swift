//
//  EmptyStateView.swift
//  Reader for Language Learner
//
//  Extracted from ContentView.swift
//

import SwiftUI

struct EmptyStateView: View {
    let onOpenPDF: () -> Void
    var recentDocuments: [RecentDocument] = []
    var todayReadingTime: Double = 0
    var reviewedTodayCount: Int = 0
    var noteStore: PDFNoteStore? = nil
    var savedWordsStore: SavedWordsStore? = nil
    var bookmarkStore: PDFBookmarkStore? = nil
    var onOpenRecent: ((RecentDocument) -> Void)? = nil
    var onReview: (() -> Void)? = nil

    private var pendingReviewCount: Int {
        savedWordsStore?.pendingReviewCount ?? 0
    }

    private var hasDashboardData: Bool {
        !recentDocuments.isEmpty
            || todayReadingTime > 0
            || reviewedTodayCount > 0
            || (savedWordsStore?.words.isEmpty == false)
            || (noteStore?.notes.isEmpty == false)
            || (bookmarkStore?.bookmarks.isEmpty == false)
    }

    var body: some View {
        ZStack {
            DS.Color.surface
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                    DashboardActionBar(
                        pendingReviewCount: pendingReviewCount,
                        hasSavedWords: savedWordsStore?.words.isEmpty == false,
                        onOpenPDF: onOpenPDF,
                        onReview: onReview
                    )

                    DashboardWorklaneRow(
                        recentDocumentCount: recentDocuments.count,
                        pendingReviewCount: pendingReviewCount,
                        reviewedTodayCount: reviewedTodayCount,
                        noteCount: noteStore?.notes.count ?? 0,
                        savedWordCount: savedWordsStore?.words.count ?? 0,
                        onOpenPDF: onOpenPDF,
                        onReview: onReview
                    )

                    WorkspaceSummaryView(
                        todayReadingTime: todayReadingTime,
                        pendingReviewCount: pendingReviewCount,
                        reviewedTodayCount: reviewedTodayCount,
                        noteCount: noteStore?.notes.count ?? 0,
                        savedWordCount: savedWordsStore?.words.count ?? 0,
                        bookmarkCount: bookmarkStore?.bookmarks.count ?? 0,
                        reviewActivity: savedWordsStore?.reviewActivity(days: 365) ?? []
                    )

                    if !recentDocuments.isEmpty {
                        recentDocumentsSection
                    } else if !hasDashboardData {
                        EmptyDashboardPlaceholder()
                    }
                }
                .frame(maxWidth: 980, alignment: .topLeading)
                .frame(maxWidth: .infinity, minHeight: 620, alignment: .top)
                .padding(.horizontal, DS.Spacing.xl)
                .padding(.vertical, DS.Spacing.xl)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var recentDocumentsSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("Continue Reading")
                    .font(DS.Typography.headline)
                    .foregroundStyle(DS.Color.textPrimary)
                Spacer()
                Text("\(recentDocuments.count) recent")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 214, maximum: 260), spacing: DS.Spacing.md)],
                alignment: .leading,
                spacing: DS.Spacing.md
            ) {
                ForEach(recentDocuments.prefix(4)) { document in
                    CompactRecentDocumentCard(
                        document: document,
                        noteCount: noteStore?.count(for: document.filename) ?? 0,
                        savedWordCount: savedWordsStore?.savedCount(for: document.filename) ?? 0,
                        dueWordCount: savedWordsStore?.dueCount(for: document.filename) ?? 0,
                        bookmarkCount: bookmarkStore?.bookmarks(for: document.filename).count ?? 0,
                        onOpen: { onOpenRecent?(document) },
                        onReview: onReview
                    )
                }
            }
        }
    }
}

private struct DashboardActionBar: View {
    let pendingReviewCount: Int
    let hasSavedWords: Bool
    let onOpenPDF: () -> Void
    let onReview: (() -> Void)?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            horizontalLayout
            verticalLayout
        }
        .padding(DS.Spacing.md)
        .background(statusColor.opacity(0.05))
        .background(DS.Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .strokeBorder(DS.Color.separator.opacity(0.28), lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(statusColor)
                .frame(width: 3)
        }
    }

    private var horizontalLayout: some View {
        HStack(spacing: DS.Spacing.md) {
            statusBlock
            Spacer(minLength: DS.Spacing.md)
            actions
        }
    }

    private var verticalLayout: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            statusBlock
            actions
        }
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: statusIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .frame(width: 16)
                Text(statusText)
                    .font(DS.Typography.headline)
                    .foregroundStyle(DS.Color.textPrimary)
                    .lineLimit(1)
            }
            Label("Drop a PDF anywhere in this window", systemImage: "arrow.down.to.line")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.textTertiary)
                .lineLimit(1)
        }
    }

    private var actions: some View {
        HStack(spacing: DS.Spacing.sm) {
            if let onReview {
                Button(action: onReview) {
                    Label(
                        pendingReviewCount > 0 ? "Review \(pendingReviewCount)" : "Review",
                        systemImage: "brain.head.profile"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(!hasSavedWords)
            }

            Button(action: onOpenPDF) {
                Label("Open PDF", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .keyboardShortcut("o", modifiers: [.command])
        }
    }

    private var statusText: String {
        if pendingReviewCount > 0 {
            return "\(pendingReviewCount) words are ready for review"
        }
        if hasSavedWords {
            return "Keep reading and reviewing"
        }
        return "Start with a PDF"
    }

    private var statusIcon: String {
        pendingReviewCount > 0 ? "clock.badge.exclamationmark" : "doc.text"
    }

    private var statusColor: Color {
        pendingReviewCount > 0 ? DS.Color.warning : DS.Color.accent
    }
}

private struct DashboardWorklaneRow: View {
    let recentDocumentCount: Int
    let pendingReviewCount: Int
    let reviewedTodayCount: Int
    let noteCount: Int
    let savedWordCount: Int
    let onOpenPDF: () -> Void
    let onReview: (() -> Void)?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Spacing.md) {
                cards
            }
            VStack(spacing: DS.Spacing.sm) {
                cards
            }
        }
    }

    @ViewBuilder
    private var cards: some View {
        DashboardLaneCard(
            title: "Reading",
            value: recentDocumentCount > 0 ? "\(recentDocumentCount) recent" : "Open a PDF",
            detail: recentDocumentCount > 0 ? "Continue from your library" : "Start a reading session",
            icon: "book.pages",
            tint: DS.Color.accent,
            actionTitle: "Open",
            action: onOpenPDF
        )

        DashboardLaneCard(
            title: "Review",
            value: pendingReviewCount > 0 ? "\(pendingReviewCount) due" : "\(reviewedTodayCount) today",
            detail: savedWordCount > 0 ? "\(savedWordCount) saved words" : "Save words while reading",
            icon: pendingReviewCount > 0 ? "clock.badge.exclamationmark" : "checkmark.circle",
            tint: pendingReviewCount > 0 ? DS.Color.warning : DS.Color.success,
            actionTitle: "Review",
            action: onReview,
            isDisabled: savedWordCount == 0
        )

        DashboardLaneCard(
            title: "Notes",
            value: "\(noteCount) notes",
            detail: noteCount > 0 ? "Search and revisit later" : "Create notes from PDFs",
            icon: "note.text",
            tint: .purple
        )
    }
}

private struct DashboardLaneCard: View {
    let title: String
    let value: String
    let detail: String
    let icon: String
    let tint: Color
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var isDisabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 16)
                Text(title)
                    .font(DS.Typography.caption.weight(.semibold))
                    .foregroundStyle(DS.Color.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: DS.Spacing.sm)
            }

            Text(value)
                .font(DS.Typography.headline)
                .foregroundStyle(DS.Color.textPrimary)
                .lineLimit(1)

            HStack(spacing: DS.Spacing.sm) {
                Text(detail)
                    .font(DS.Typography.caption2)
                    .foregroundStyle(DS.Color.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: DS.Spacing.xs)

                if let action, let actionTitle {
                    Button(actionTitle, action: action)
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .disabled(isDisabled)
                }
            }
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.055))
        .background(DS.Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .strokeBorder(tint.opacity(0.28), lineWidth: 1)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(tint)
                .frame(height: 2)
        }
    }
}

private struct EmptyDashboardPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "doc.text")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Color.textSecondary)
                Text("No documents yet")
                    .font(DS.Typography.label)
                    .foregroundStyle(DS.Color.textPrimary)
            }

            Text("Open or drop a PDF to create reading history, saved words, notes, and review activity.")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .strokeBorder(DS.Color.separator.opacity(0.24), lineWidth: 1)
        )
    }
}

private struct CompactRecentDocumentCard: View {
    let document: RecentDocument
    let noteCount: Int
    let savedWordCount: Int
    let dueWordCount: Int
    let bookmarkCount: Int
    let onOpen: () -> Void
    let onReview: (() -> Void)?

    @State private var isHovered = false

    private var documentTint: Color {
        if dueWordCount > 0 { return DS.Color.warning }
        if savedWordCount > 0 { return DS.Color.success }
        if noteCount > 0 { return .purple }
        return DS.Color.accent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(document.filename)
                        .font(DS.Typography.label)
                        .foregroundStyle(DS.Color.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(document.lastOpenedAt, style: .relative)
                        .font(DS.Typography.caption2)
                        .foregroundStyle(DS.Color.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: DS.Spacing.sm)

                Text(document.pageLabel)
                    .font(DS.Typography.caption2.weight(.semibold))
                    .foregroundStyle(DS.Color.textSecondary)
                    .lineLimit(1)
            }

            HStack(spacing: DS.Spacing.sm) {
                metric(icon: "note.text", value: noteCount)
                metric(icon: "star", value: savedWordCount, tint: .yellow)
                metric(icon: "clock", value: dueWordCount, tint: dueWordCount > 0 ? DS.Color.warning : DS.Color.textSecondary)
                metric(icon: "bookmark", value: bookmarkCount, tint: .purple)
            }

            Text(document.url.lastPathComponent)
                .font(DS.Typography.caption2)
                .foregroundStyle(DS.Color.textTertiary)
                .lineLimit(1)

            HStack(spacing: DS.Spacing.sm) {
                Button(action: onOpen) {
                    Label("Continue", systemImage: "arrow.right")
                        .font(DS.Typography.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                if let onReview {
                    Button(action: onReview) {
                        Text(dueWordCount > 0 ? "Review \(dueWordCount)" : "Review")
                            .font(DS.Typography.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(savedWordCount == 0)
                }
            }
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(documentTint.opacity(isHovered ? 0.08 : 0.045))
        .background(DS.Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .strokeBorder(isHovered ? documentTint.opacity(0.42) : DS.Color.separator.opacity(0.26), lineWidth: 1)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(documentTint)
                .frame(height: 2)
        }
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        .animation(DS.Animation.fast, value: isHovered)
        .onHover { isHovered = $0 }
    }

    private func metric(icon: String, value: Int, tint: Color = DS.Color.textSecondary) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
            Text("\(value)")
                .font(DS.Typography.caption2.weight(.medium))
        }
        .foregroundStyle(DS.Color.textSecondary)
        .lineLimit(1)
    }
}
