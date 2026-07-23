//
//  SidebarView.swift
//  Reader for Language Learner
//

import PDFKit
import SwiftUI

// MARK: - Sidebar Tab

enum SidebarTab: String, CaseIterable, Identifiable {
    case thumbnails  = "Pages"
    case outline     = "Contents"
    case annotations = "Annotations"
    case words       = "Words"
    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .thumbnails:  return "square.grid.2x2"
        case .outline:     return "list.bullet.rectangle"
        case .annotations: return "bookmark"
        case .words:       return "character.book.closed"
        }
    }

    /// All four base symbols have a matching `.fill` variant.
    var selectedIconName: String { iconName + ".fill" }

    /// User-facing tab title (raw values stay English — they key persistence).
    var localizedTitle: String {
        switch self {
        case .thumbnails:  return String(localized: "Pages")
        case .outline:     return String(localized: "Contents")
        case .annotations: return String(localized: "Annotations")
        case .words:       return String(localized: "Words")
        }
    }
}

extension Notification.Name {
    /// Posted from a Spotlight deep link; object is the SavedWord UUID.
    static let revealSavedWordCommand = Notification.Name("revealSavedWordCommand")
}

// MARK: - SidebarView

struct SidebarView: View {
    var pdfViewManager:  PDFViewManager
    var savedWordsStore: SavedWordsStore
    var bookmarkStore:   PDFBookmarkStore
    var noteStore:       PDFNoteStore
    var highlightStore:  PDFHighlightStore
    var currentDocumentName: String?
    /// Non-nil document ⇒ the window is showing an EPUB.
    var epubManager: EPUBViewManager? = nil
    var epubHighlightStore: EPUBHighlightStore
    var epubBookmarkStore: EPUBBookmarkStore
    var epubNoteStore: EPUBNoteStore

    @State private var selectedTab: SidebarTab = .thumbnails
    @AppStorage("thumbnailSize") private var thumbnailSizeRaw = DS.ThumbnailSize.medium.rawValue

    private var thumbnailSize: DS.ThumbnailSize {
        DS.ThumbnailSize(rawValue: thumbnailSizeRaw) ?? .medium
    }

    private var isEPUB: Bool { epubManager?.document != nil }

    /// Page thumbnails are a PDF concept — the tab disappears for EPUBs.
    private var availableTabs: [SidebarTab] {
        isEPUB ? [.outline, .annotations, .words] : SidebarTab.allCases
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            tabContent
        }
        // No explicit material: the NavigationSplitView sidebar column
        // already provides the standard sidebar background.
        .onReceive(NotificationCenter.default.publisher(for: .revealSavedWordCommand)) { _ in
            // Spotlight deep link: the word list handles selection; this
            // just makes sure the Words tab is frontmost.
            withAnimation(DS.Animation.springFast) { selectedTab = .words }
        }
        .onChange(of: isEPUB) { _, _ in normalizeSelectedTab() }
        .onAppear { normalizeSelectedTab() }
    }

    private func normalizeSelectedTab() {
        if !availableTabs.contains(selectedTab) {
            selectedTab = .outline
        }
    }

    // MARK: - Icon Tab Bar

    private var tabBar: some View {
        // Glass container so the selected-tab chip samples a shared region,
        // matching the inspector's control language.
        DSGlassGroup(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(availableTabs) { tab in
                    tabBarButton(tab)
                }
            }
        }
        .padding(.horizontal, DS.Spacing.xs)
        .padding(.top, DS.Spacing.sm)
        .padding(.bottom, DS.Spacing.xs)
    }

    private func tabBarButton(_ tab: SidebarTab) -> some View {
        let isSelected = selectedTab == tab
        let badgeCount = badgeCount(for: tab)
        return Button {
            withAnimation(DS.Animation.springFast) { selectedTab = tab }
        } label: {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: isSelected ? tab.selectedIconName : tab.iconName)
                        .font(DS.Typography.icon(14, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? DS.Color.accent : DS.Color.textSecondary)
                        // Fixed box so every symbol centers identically
                        // regardless of its intrinsic width/baseline.
                        .frame(width: 22, height: 17)

                    if badgeCount > 0 {
                        Text("\(min(badgeCount, 99))")
                            .font(DS.Typography.micro(8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(DS.Color.accent)
                            .clipShape(Capsule())
                            .offset(x: 6, y: -4)
                    }
                }

                Text(tab.localizedTitle)
                    .font(DS.Typography.micro(9, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? DS.Color.accent : DS.Color.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.xs)
            .background {
                // Selected tab = accent-tinted glass chip on macOS 26, the flat
                // accentSubtle wash on macOS 15 (glass carries the accent, the
                // glyph/label color signals selection on both paths).
                if isSelected {
                    Color.clear
                        .dsGlassInteractive(
                            cornerRadius: DS.Radius.sm,
                            // Neutral glass — the accent-colored icon/label signals
                            // selection. An accent tint would match (and hide) the
                            // accent-colored label. Fallback keeps the 15 wash.
                            tint: nil,
                            fallback: AnyShapeStyle(DS.Color.accentSubtle),
                            fallbackStroke: .none
                        )
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
        }
        .buttonStyle(.plain)
        .help(tab.localizedTitle)
        .accessibilityLabel(tab.localizedTitle)
        .accessibilityValue(accessibilityValue(isSelected: isSelected, badgeCount: badgeCount, tab: tab))
        .accessibilityHint(String(localized: "Switch to \(tab.localizedTitle) tab"))
    }

    private func badgeCount(for tab: SidebarTab) -> Int {
        switch tab {
        case .annotations:
            if isEPUB {
                return epubBookmarkStore.count(for: currentDocumentName)
                    + epubHighlightStore.count(for: currentDocumentName)
                    + epubNoteStore.count(for: currentDocumentName)
            }
            let marks = currentDocumentName.map { bookmarkStore.bookmarks(for: $0).count } ?? 0
            return marks
                + highlightStore.count(for: currentDocumentName)
                + noteStore.count(for: currentDocumentName)
        case .words:
            // Show the actionable due count rather than the full library size.
            return savedWordsStore.pendingReviewCount
        default:
            return 0
        }
    }

    private func accessibilityValue(isSelected: Bool, badgeCount: Int, tab: SidebarTab) -> String {
        let selection = isSelected ? "Selected" : ""
        guard badgeCount > 0 else { return selection }

        let countText: String
        switch tab {
        case .words:
            countText = "\(badgeCount) words due"
        case .annotations:
            countText = "\(badgeCount) annotations for this document"
        default:
            countText = "\(badgeCount) items"
        }

        return selection.isEmpty ? countText : "\(selection), \(countText)"
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .thumbnails:
            VStack(spacing: 0) {
                // Size picker toolbar
                HStack {
                    Spacer()
                    Picker("", selection: Binding(
                        get: { thumbnailSize },
                        set: { thumbnailSizeRaw = $0.rawValue }
                    )) {
                        ForEach(DS.ThumbnailSize.allCases) { size in
                            Text(size.rawValue).tag(size)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .controlSize(.mini)
                    .frame(width: 72)
                    .padding(.trailing, DS.Spacing.sm)
                }
                .padding(.vertical, DS.Spacing.xs)
                Divider()
                PDFThumbnailSidebarView(
                    pdfViewManager: pdfViewManager,
                    thumbnailSize: thumbnailSize,
                    bookmarkStore: bookmarkStore,
                    currentDocumentName: currentDocumentName
                )
            }
        case .outline:
            if let epubManager, isEPUB {
                EPUBOutlineView(manager: epubManager)
            } else {
                PDFOutlineView(pdfViewManager: pdfViewManager)
            }
        case .annotations:
            AnnotationsView(
                bookmarkStore:   bookmarkStore,
                highlightStore:  highlightStore,
                noteStore:       noteStore,
                savedWordsStore: savedWordsStore,
                pdfViewManager:  pdfViewManager,
                currentFilename: currentDocumentName,
                epubManager:        isEPUB ? epubManager : nil,
                epubHighlightStore: epubHighlightStore,
                epubBookmarkStore:  epubBookmarkStore,
                epubNoteStore:      epubNoteStore
            )
        case .words:
            WordsView(
                store: savedWordsStore,
                currentDocumentName: currentDocumentName
            )
        }
    }
}
