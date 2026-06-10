//
//  EmptyStateView.swift
//  Reader for Language Learner
//
//  Welcome dashboard shown when no PDF is open.
//
//  Design intent: calm, focused, premium. One accent color, one review CTA,
//  a single hero action (continue the last document), quiet metadata.
//  No repeated counts, no zero-value badges, no per-card button clusters.
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

    private var hasSavedWords: Bool {
        savedWordsStore?.words.isEmpty == false
    }

    private var heroDocument: RecentDocument? {
        recentDocuments.first
    }

    private var otherDocuments: [RecentDocument] {
        Array(recentDocuments.dropFirst().prefix(4))
    }

    var body: some View {
        ZStack {
            DS.Color.surface
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                    DashboardHeader(onOpenPDF: onOpenPDF)

                    if let heroDocument {
                        ContinueReadingHero(
                            document: heroDocument,
                            todayReadingTime: todayReadingTime,
                            onOpen: onOpenRecent.map { open in { open(heroDocument) } }
                        )
                    } else {
                        EmptyLibraryHero(onOpenPDF: onOpenPDF)
                    }

                    if pendingReviewCount > 0, let onReview {
                        ReviewPromptRow(
                            pendingReviewCount: pendingReviewCount,
                            onReview: onReview
                        )
                    }

                    if !otherDocuments.isEmpty {
                        RecentDocumentList(
                            documents: otherDocuments,
                            onOpen: onOpenRecent
                        )
                    }

                    Spacer(minLength: DS.Spacing.xl)

                    DashboardFooter(
                        savedWordCount: savedWordsStore?.words.count ?? 0,
                        noteCount: noteStore?.notes.count ?? 0,
                        bookmarkCount: bookmarkStore?.bookmarks.count ?? 0,
                        reviewedTodayCount: reviewedTodayCount,
                        reviewStreak: currentReviewStreak
                    )
                }
                .frame(maxWidth: 640, alignment: .topLeading)
                .frame(maxWidth: .infinity, minHeight: 560, alignment: .top)
                .padding(.horizontal, DS.Spacing.xxl)
                .padding(.top, DS.Spacing.xxxl)
                .padding(.bottom, DS.Spacing.xl)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var currentReviewStreak: Int {
        guard let activity = savedWordsStore?.reviewActivity(days: 60) else { return 0 }
        var streak = 0
        for day in activity.reversed() {
            if day.count > 0 {
                streak += 1
            } else if streak > 0 {
                break
            }
        }
        return streak
    }
}

// MARK: - Header

private struct DashboardHeader: View {
    let onOpenPDF: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(greeting)
                    .font(.system(size: 26, weight: .semibold, design: .default))
                    .foregroundStyle(DS.Color.textPrimary)
                Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(DS.Typography.subhead)
                    .foregroundStyle(DS.Color.textTertiary)
            }

            Spacer()

            Button(action: onOpenPDF) {
                Label("Open PDF", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut("o", modifiers: [.command])
            .help("Open a PDF (⌘O)")
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12:  return "Good morning"
        case 12..<18: return "Good afternoon"
        default:      return "Good evening"
        }
    }
}

// MARK: - Continue Reading Hero

private struct ContinueReadingHero: View {
    let document: RecentDocument
    let todayReadingTime: Double
    var onOpen: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        Button {
            onOpen?()
        } label: {
            HStack(alignment: .center, spacing: DS.Spacing.lg) {
                Image(systemName: "book.pages")
                    .font(.system(size: 21, weight: .light))
                    .foregroundStyle(DS.Color.accent)
                    .frame(width: 52, height: 52)
                    .background(DS.Color.accentSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))

                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("Continue reading")
                        .dsOverlineLabel()
                        .textCase(.uppercase)

                    Text(displayTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(DS.Color.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(metaText)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: DS.Spacing.lg)

                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isHovered ? DS.Color.accent : DS.Color.textTertiary)
            }
            .padding(DS.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Color.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .strokeBorder(
                        isHovered ? DS.Color.accentMuted : DS.Color.separator.opacity(0.3),
                        lineWidth: 1
                    )
            )
            .dsShadow(isHovered ? DS.Shadow.card : DS.Shadow.subtle)
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
        }
        .buttonStyle(.plain)
        .disabled(onOpen == nil)
        .animation(DS.Animation.fast, value: isHovered)
        .onHover { isHovered = $0 }
        .accessibilityLabel("Continue reading \(displayTitle), \(document.pageLabel)")
    }

    private var displayTitle: String {
        document.filename
            .replacingOccurrences(of: ".pdf", with: "", options: [.caseInsensitive, .anchored, .backwards])
            .replacingOccurrences(of: "_", with: " ")
    }

    private var metaText: String {
        var parts = [document.pageLabel]
        if todayReadingTime > 0,
           let formatted = Self.durationFormatter.string(from: todayReadingTime) {
            parts.append("\(formatted) today")
        }
        parts.append(relativeOpenedText)
        return parts.joined(separator: "  ·  ")
    }

    private var relativeOpenedText: String {
        Self.relativeFormatter.localizedString(for: document.lastOpenedAt, relativeTo: .now)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        formatter.zeroFormattingBehavior = .dropAll
        return formatter
    }()
}

// MARK: - Review Prompt

private struct ReviewPromptRow: View {
    let pendingReviewCount: Int
    let onReview: () -> Void

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            Circle()
                .fill(DS.Color.warning)
                .frame(width: 7, height: 7)

            Text(pendingReviewCount == 1
                 ? "1 word is ready for review"
                 : "\(pendingReviewCount) words are ready for review")
                .font(DS.Typography.label)
                .foregroundStyle(DS.Color.textPrimary)

            Spacer(minLength: DS.Spacing.md)

            Button("Review", action: onReview)
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help("Start a review session")
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
        .background(DS.Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .strokeBorder(DS.Color.separator.opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(pendingReviewCount) words ready for review")
    }
}

// MARK: - Recent Documents

private struct RecentDocumentList: View {
    let documents: [RecentDocument]
    var onOpen: ((RecentDocument) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Recent")
                .dsOverlineLabel()
                .textCase(.uppercase)
                .padding(.leading, DS.Spacing.xs)

            VStack(spacing: 0) {
                ForEach(Array(documents.enumerated()), id: \.element.id) { index, document in
                    RecentDocumentRow(
                        document: document,
                        onOpen: onOpen.map { open in { open(document) } }
                    )
                    if index < documents.count - 1 {
                        Divider()
                            .padding(.leading, DS.Spacing.lg + 16)
                    }
                }
            }
            .background(DS.Color.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .strokeBorder(DS.Color.separator.opacity(0.3), lineWidth: 1)
            )
        }
    }
}

private struct RecentDocumentRow: View {
    let document: RecentDocument
    var onOpen: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        Button {
            onOpen?()
        } label: {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: "doc.text")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(DS.Color.textTertiary)
                    .frame(width: 16)

                Text(displayTitle)
                    .font(DS.Typography.label)
                    .foregroundStyle(DS.Color.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: DS.Spacing.md)

                Text(document.pageLabel)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
                    .lineLimit(1)

                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.Color.accent)
                    .opacity(isHovered ? 1 : 0)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.md)
            .background(isHovered ? DS.Color.hoverOverlay : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onOpen == nil)
        .animation(DS.Animation.fast, value: isHovered)
        .onHover { isHovered = $0 }
        .accessibilityLabel("Open \(displayTitle), \(document.pageLabel)")
    }

    private var displayTitle: String {
        document.filename
            .replacingOccurrences(of: ".pdf", with: "", options: [.caseInsensitive, .anchored, .backwards])
            .replacingOccurrences(of: "_", with: " ")
    }
}

// MARK: - Empty Library Hero

private struct EmptyLibraryHero: View {
    let onOpenPDF: () -> Void

    var body: some View {
        VStack(spacing: DS.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(DS.Color.accentSubtle)
                    .frame(width: 76, height: 76)
                Image(systemName: "book.pages")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(DS.Color.accent)
            }

            VStack(spacing: DS.Spacing.xs) {
                Text("Start with a PDF")
                    .font(DS.Typography.title)
                    .foregroundStyle(DS.Color.textPrimary)
                Text("Open a document, select words as you read,\nand build your vocabulary.")
                    .font(DS.Typography.subhead)
                    .foregroundStyle(DS.Color.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.xxxl)
    }
}

// MARK: - Footer

private struct DashboardFooter: View {
    let savedWordCount: Int
    let noteCount: Int
    let bookmarkCount: Int
    let reviewedTodayCount: Int
    let reviewStreak: Int

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Divider()

            HStack(spacing: DS.Spacing.sm) {
                if !statsText.isEmpty {
                    Text(statsText)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: DS.Spacing.md)

                Label("Drop a PDF anywhere to open it", systemImage: "arrow.down.doc")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    private var statsText: String {
        var parts: [String] = []
        if savedWordCount > 0 {
            parts.append(savedWordCount == 1 ? "1 saved word" : "\(savedWordCount) saved words")
        }
        if noteCount > 0 {
            parts.append(noteCount == 1 ? "1 note" : "\(noteCount) notes")
        }
        if bookmarkCount > 0 {
            parts.append(bookmarkCount == 1 ? "1 bookmark" : "\(bookmarkCount) bookmarks")
        }
        if reviewedTodayCount > 0 {
            parts.append("\(reviewedTodayCount) reviewed today")
        }
        if reviewStreak > 1 {
            parts.append("\(reviewStreak)-day streak")
        }
        return parts.joined(separator: "  ·  ")
    }
}
