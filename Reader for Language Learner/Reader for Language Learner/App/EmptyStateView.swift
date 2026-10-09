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
                            .frame(maxWidth: DS.Layout.libraryContentWidth, alignment: .topLeading)
                        } else {
                            dashboardColumn
                                .frame(maxWidth: DS.Layout.dashboardContentWidth, alignment: .topLeading)
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
                .frame(maxWidth: DS.Layout.dashboardContentWidth)
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

            // Today's work in the order it's usually done: pick the book
            // back up, clear the reviews, then the reading goal.
            // Today's reviews and today's reading side by side (v14 S3):
            // each is one number and one thing to do.
            HStack(alignment: .top, spacing: DS.Spacing.md) {
                if let savedWordsStore, hasSavedWords {
                    DashboardWordCard(
                        store: savedWordsStore,
                        onReviewAll: onReview
                    )
                    .frame(maxWidth: .infinity)
                }

                if let sessionStore, heroDocument != nil {
                    DashboardActivityCard(
                        todayReadingTime: todayReadingTime,
                        last7Days: sessionStore.last7Days,
                        readingStreak: sessionStore.currentStreak,
                        streakAtRisk: sessionStore.isStreakAtRisk
                    )
                    .frame(maxWidth: .infinity)
                }
            }

            if let savedWordsStore {
                KindleNoticeBanner(store: savedWordsStore)
            }

            DashboardToolsRow(onReview: onReview)

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
    private func bookWords(for document: RecentDocument) -> [SavedWord]? {
        guard let savedWordsStore else { return nil }
        return BookWords(document: BookIdentity.Document(path: document.path, names: [document.filename]),
                         words: savedWordsStore.words, encounters: [],
                         matchingTitles: BookWords.matchesTitles(forDocumentAt: document.path)).saved
    }

    private func documentStats(for document: RecentDocument) -> DocumentStats {
        DocumentStats(
            readingTime: sessionStore?.totalTime(for: document.url.lastPathComponent) ?? 0,
            // The book's words, copies and Kindle included (v16 S3).
            savedWords: bookWords(for: document)?.count ?? 0,
            dueWords: bookWords(for: document).map { words in words.count { savedWordsStore?.isDue($0) == true } } ?? 0,
            notes: noteStore?.count(for: document.filename) ?? 0,
            bookmarks: bookmarkStore?.bookmarks(for: document.filename).count ?? 0,
            progress: document.readingProgress,
            pageLabel: document.pageLabel,
            coverage: document.coverage?.profile
        )
    }

}

// MARK: - Header

private struct DashboardHeader: View {
    let onOpenPDF: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text("Today")
                    .font(DS.Typography.title)
                    .foregroundStyle(DS.Color.textPrimary)
                Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(DS.Typography.subhead)
                    .foregroundStyle(DS.Color.textTertiary)
            }

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

// MARK: - Tools

/// The tools that open their own window or sheet, in one place (v14 S3).
/// Before, each was reachable only from a menu or ⌘K.
private struct DashboardToolsRow: View {
    var onReview: (() -> Void)?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Tools")
                .dsOverlineLabel()
                .textCase(.uppercase)
            HStack(spacing: DS.Spacing.md) {
                tile("Import Web Article", detail: "Read a web page like a book", icon: "globe") {
                    NotificationCenter.default.post(name: .importWebArticleCommand, object: nil)
                }
                tile("Story From Your Words", detail: "A short story with the words due", icon: "text.book.closed") {
                    NotificationCenter.default.post(name: .wordStoryCommand, object: nil)
                }
                tile("Word Notebook", detail: "Every saved word, by book and deck", icon: "character.book.closed") {
                    openWindow(id: WordNotebook.windowID)
                }
                if let onReview {
                    tile("Study Room", detail: "Study cards in their own window", icon: "rectangle.stack", action: onReview)
                }
            }
        }
    }

    private func tile(
        _ title: LocalizedStringKey, detail: LocalizedStringKey, icon: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Image(systemName: icon)
                    .font(DS.Typography.icon(15, weight: .medium))
                    .foregroundStyle(DS.Color.accent)
                    // Same box for every symbol, so the titles line up.
                    .frame(width: 22, height: 20, alignment: .leading)
                    .padding(.bottom, DS.Spacing.xxs)
                Text(title)
                    .font(DS.Typography.label)
                    .foregroundStyle(DS.Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(detail)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DS.Spacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .dsCard(padding: nil, radius: DS.Radius.md, stroke: .hairline)
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Continue Reading Hero

private struct ContinueReadingHero: View {
    let document: RecentDocument
    let todayReadingTime: Double
    var cover: NSImage?
    var onOpen: (() -> Void)?

    @AppStorage(StorageKey.readingRecapEnabled) private var recapEnabled = true

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
                        .font(DS.Typography.title)
                        .foregroundStyle(DS.Color.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(metaText)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                        .lineLimit(1)

                    if recapEnabled, fileExists,
                       let days = ReadingRecap.daysAway(
                           lastOpenedAt: document.lastOpenedAt,
                           hasProgress: (document.lastPageIndex ?? 0) > 0
                       ) {
                        Label(
                            String(localized: "\(days) days away — you'll get a short recap when you open it"),
                            systemImage: "clock.arrow.circlepath"
                        )
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.accent)
                        .lineLimit(1)
                    }
                }

                Spacer(minLength: DS.Spacing.lg)

                // The card is the button; this says what it does (v14 S3).
                Text("Continue")
                    .font(DS.Typography.callout.weight(.semibold))
                    .foregroundStyle(SwiftUI.Color.white)
                    .padding(.horizontal, DS.Spacing.md)
                    .padding(.vertical, DS.Spacing.xs + 1)
                    .background(isHovered ? DS.Color.accentStrong : DS.Color.accent, in: Capsule())
                    .fixedSize()
            }
            .padding(DS.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            // First background sits closest to the content — the wash reads
            // over the opaque surface behind it.
            .background(DS.Gradient.accentWash)
            .background(DS.Color.surfaceElevated)
            .overlay(alignment: .bottom) {
                if let progress = document.readingProgress {
                    DSProgressBar(value: progress)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .strokeBorder(
                        isHovered ? DS.Color.accentMuted : DS.Color.hairline,
                        lineWidth: 1
                    )
            )
            // Stronger hover lift (card → float) so the hero feels like it
            // rises toward the pointer, matching the app's glass polish.
            .dsShadow(isHovered ? DS.Shadow.float : DS.Shadow.subtle)
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
        }
        .buttonStyle(.plain)
        .disabled(onOpen == nil || !fileExists)
        .opacity(fileExists ? 1 : 0.55)
        .animation(DS.Animation.fast, value: isHovered)
        .onHover { isHovered = $0 }
        .contextMenu {
            if let onOpen {
                Button("Open", action: onOpen)
                    .disabled(!fileExists)
                Divider()
            }
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
                .frame(width: DS.Layout.coverHero.width, height: DS.Layout.coverHero.height)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                        .strokeBorder(DS.Color.hairlineStrong, lineWidth: 0.5)
                )
                .transition(.opacity)
        } else {
            DSCoverPlaceholder(iconSize: 21)
                .frame(width: DS.Layout.coverHero.width, height: DS.Layout.coverHero.height)
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
                                .font(DS.Typography.icon(8, weight: .semibold))
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
            .dsCard(padding: nil, radius: DS.Radius.md, stroke: .hairline)
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

                if let coverage = document.coverage?.profile, coverage.totalTokens > 0 {
                    CoverageBadge(profile: coverage)
                }

                Text(trailingText)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
                    .lineLimit(1)

                Image(systemName: "arrow.right")
                    .font(DS.Typography.icon(10, weight: .semibold))
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
            if let onOpen {
                Button("Open", action: onOpen)
                    .disabled(!fileExists)
                Divider()
            }
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
                .frame(width: DS.Layout.coverMini.width, height: DS.Layout.coverMini.height)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(DS.Color.hairlineStrong, lineWidth: 0.5)
                )
                .transition(.opacity)
        } else {
            DSCoverPlaceholder(iconSize: 12, fileExists: fileExists)
                .frame(width: DS.Layout.coverMini.width, height: DS.Layout.coverMini.height)
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
                    .font(DS.Typography.iconHero)
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
