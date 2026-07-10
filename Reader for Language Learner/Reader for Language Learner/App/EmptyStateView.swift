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

import AppKit
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
    var onRemoveRecent: ((RecentDocument) -> Void)? = nil
    var onReview: (() -> Void)? = nil
    var coverStore: DocumentCoverStore? = nil
    var sessionStore: ReadingSessionStore? = nil

    @State private var showLibrary = false

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

            VStack(spacing: 0) {
                ScrollView {
                    Group {
                        if showLibrary {
                            LibraryView(
                                documents: recentDocuments,
                                coverStore: coverStore,
                                onOpen: onOpenRecent,
                                onRemove: onRemoveRecent,
                                statsProvider: documentStats(for:),
                                onBack: { showLibrary = false }
                            )
                            .frame(maxWidth: 880, alignment: .topLeading)
                        } else {
                            dashboardColumn
                                .frame(maxWidth: 640, alignment: .topLeading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(.horizontal, DS.Spacing.xxl)
                    .padding(.top, showLibrary ? DS.Spacing.xl : DS.Spacing.xxxl)
                    .padding(.bottom, DS.Spacing.xl)
                    .animation(DS.Animation.standard, value: showLibrary)
                }

                DashboardFooter(
                    savedWordCount: savedWordsStore?.words.count ?? 0,
                    noteCount: noteStore?.notes.count ?? 0,
                    bookmarkCount: bookmarkStore?.bookmarks.count ?? 0,
                    reviewedTodayCount: reviewedTodayCount
                )
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, DS.Spacing.xxl)
                .padding(.bottom, DS.Spacing.lg)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: recentDocuments.prefix(5).map(\.path)) {
            for document in recentDocuments.prefix(5) {
                coverStore?.requestCover(for: document.path)
            }
        }
    }

    private var dashboardColumn: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xl) {
            DashboardHeader(onOpenPDF: onOpenPDF)

            if let heroDocument {
                ContinueReadingHero(
                    document: heroDocument,
                    todayReadingTime: todayReadingTime,
                    cover: cover(for: heroDocument),
                    onOpen: onOpenRecent.map { open in { open(heroDocument) } }
                )
            } else {
                EmptyLibraryHero(onOpenPDF: onOpenPDF)
            }

            if let sessionStore, heroDocument != nil {
                DashboardActivityCard(
                    todayReadingTime: todayReadingTime,
                    last7Days: sessionStore.last7Days,
                    readingStreak: sessionStore.currentStreak,
                    streakAtRisk: sessionStore.isStreakAtRisk
                )
            }

            if let savedWordsStore, hasSavedWords {
                DashboardWordCard(
                    store: savedWordsStore,
                    onReviewAll: onReview
                )
            }

            if !otherDocuments.isEmpty {
                RecentDocumentList(
                    documents: otherDocuments,
                    onOpen: onOpenRecent,
                    onRemove: onRemoveRecent,
                    coverProvider: { self.cover(for: $0) },
                    onViewAll: recentDocuments.count > 5 ? { showLibrary = true } : nil
                )
            }
        }
    }

    /// Reads `revision` so SwiftUI re-renders when a cover finishes loading.
    private func cover(for document: RecentDocument) -> NSImage? {
        guard let coverStore else { return nil }
        _ = coverStore.revision
        return coverStore.cover(for: document.path)
    }

    /// Builds per-document stats, bridging the two filename keyings: reading
    /// sessions key on the file name with extension, while saved words / notes
    /// / bookmarks key on the name without it.
    private func documentStats(for document: RecentDocument) -> DocumentStats {
        DocumentStats(
            readingTime: sessionStore?.totalTime(for: document.url.lastPathComponent) ?? 0,
            savedWords: savedWordsStore?.savedCount(for: document.filename) ?? 0,
            dueWords: savedWordsStore?.dueCount(for: document.filename) ?? 0,
            notes: noteStore?.count(for: document.filename) ?? 0,
            bookmarks: bookmarkStore?.bookmarks(for: document.filename).count ?? 0,
            progress: document.readingProgress,
            pageLabel: document.pageLabel
        )
    }

}

// MARK: - Header

private struct DashboardHeader: View {
    let onOpenPDF: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(DS.Typography.subhead)
                .foregroundStyle(DS.Color.textTertiary)

            Spacer()

            Button(action: onOpenPDF) {
                Label("Open", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut("o", modifiers: [.command])
            .help("Open a PDF or EPUB (⌘O)")
        }
    }
}

// MARK: - Continue Reading Hero

private struct ContinueReadingHero: View {
    let document: RecentDocument
    let todayReadingTime: Double
    var cover: NSImage?
    var onOpen: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        Button {
            onOpen?()
        } label: {
            HStack(alignment: .center, spacing: DS.Spacing.lg) {
                coverView
                    .animation(DS.Animation.standard, value: cover)

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
            .overlay(alignment: .bottom) {
                if let progress = document.readingProgress {
                    GeometryReader { geo in
                        Rectangle()
                            .fill(DS.Color.accent.opacity(0.8))
                            .frame(width: geo.size.width * progress)
                    }
                    .frame(height: 3)
                    .background(DS.Color.accent.opacity(0.1))
                    .accessibilityLabel("\(Int(progress * 100)) percent read")
                }
            }
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
        .disabled(onOpen == nil || !fileExists)
        .opacity(fileExists ? 1 : 0.55)
        .animation(DS.Animation.fast, value: isHovered)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([document.url])
            }
            .disabled(!fileExists)
        }
        .accessibilityLabel("Continue reading \(displayTitle), \(document.pageLabel)")
    }

    @ViewBuilder
    private var coverView: some View {
        if let cover {
            Image(nsImage: cover)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 52, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                        .strokeBorder(DS.Color.separator.opacity(0.4), lineWidth: 0.5)
                )
                .transition(.opacity)
        } else {
            Image(systemName: "book.pages")
                .font(.system(size: 21, weight: .light))
                .foregroundStyle(DS.Color.accent)
                .frame(width: 52, height: 68)
                .background(DS.Color.accentSubtle)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
        }
    }

    private var fileExists: Bool {
        FileManager.default.fileExists(atPath: document.path)
    }

    private var displayTitle: String {
        document.displayTitle
    }

    private var metaText: String {
        guard fileExists else {
            return String(localized: "File not found — it may have been moved or deleted")
        }
        var parts = [document.pageLabel]
        if todayReadingTime > 0,
           let formatted = Self.durationFormatter.string(from: todayReadingTime) {
            parts.append(String(localized: "\(formatted) today"))
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

// MARK: - Recent Documents

private struct RecentDocumentList: View {
    let documents: [RecentDocument]
    var onOpen: ((RecentDocument) -> Void)?
    var onRemove: ((RecentDocument) -> Void)?
    var coverProvider: (RecentDocument) -> NSImage? = { _ in nil }
    var onViewAll: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent")
                    .dsOverlineLabel()
                    .textCase(.uppercase)
                    .padding(.leading, DS.Spacing.xs)

                Spacer()

                if let onViewAll {
                    Button(action: onViewAll) {
                        HStack(spacing: DS.Spacing.xxs) {
                            Text("View all")
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .semibold))
                        }
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.accent)
                    }
                    .buttonStyle(.plain)
                    .help("Show the full library")
                }
            }

            VStack(spacing: 0) {
                ForEach(Array(documents.enumerated()), id: \.element.id) { index, document in
                    RecentDocumentRow(
                        document: document,
                        cover: coverProvider(document),
                        onOpen: onOpen.map { open in { open(document) } },
                        onRemove: onRemove.map { remove in { remove(document) } }
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
    var cover: NSImage?
    var onOpen: (() -> Void)?
    var onRemove: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        Button {
            onOpen?()
        } label: {
            HStack(spacing: DS.Spacing.md) {
                miniCover
                    .animation(DS.Animation.standard, value: cover)

                Text(displayTitle)
                    .font(DS.Typography.label)
                    .foregroundStyle(fileExists ? DS.Color.textPrimary : DS.Color.textTertiary)
                    .lineLimit(1)

                Spacer(minLength: DS.Spacing.md)

                Text(trailingText)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
                    .lineLimit(1)

                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.Color.accent)
                    .opacity(isHovered && fileExists ? 1 : 0)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.md)
            .background(isHovered ? DS.Color.hoverOverlay : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onOpen == nil || !fileExists)
        .animation(DS.Animation.fast, value: isHovered)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([document.url])
            }
            .disabled(!fileExists)

            if let onRemove {
                Divider()
                Button("Remove from Library", role: .destructive, action: onRemove)
            }
        }
        .accessibilityLabel("Open \(displayTitle), \(document.pageLabel)")
    }

    @ViewBuilder
    private var miniCover: some View {
        if let cover, fileExists {
            Image(nsImage: cover)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 22, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(DS.Color.separator.opacity(0.4), lineWidth: 0.5)
                )
                .transition(.opacity)
        } else {
            Image(systemName: fileExists ? "doc.text" : "questionmark.folder")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(DS.Color.textTertiary)
                .frame(width: 22, height: 28)
                .background(DS.Color.surfaceInset.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }

    private var fileExists: Bool {
        FileManager.default.fileExists(atPath: document.path)
    }

    private var trailingText: String {
        guard fileExists else { return String(localized: "File not found") }
        return "\(document.pageLabel)  ·  \(Self.relativeFormatter.localizedString(for: document.lastOpenedAt, relativeTo: .now))"
    }

    private var displayTitle: String {
        document.displayTitle
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
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
                Text("Start with a Book or PDF")
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

                Label("Drop a PDF or EPUB anywhere to open it", systemImage: "arrow.down.doc")
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
        return parts.joined(separator: "  ·  ")
    }
}
