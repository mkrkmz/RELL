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

    @State private var selectedTab: SidebarTab = .thumbnails
    @AppStorage("thumbnailSize") private var thumbnailSizeRaw = DS.ThumbnailSize.medium.rawValue

    private var thumbnailSize: DS.ThumbnailSize {
        DS.ThumbnailSize(rawValue: thumbnailSizeRaw) ?? .medium
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
    }

    // MARK: - Icon Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(SidebarTab.allCases) { tab in
                tabBarButton(tab)
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
                        .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? DS.Color.accent : DS.Color.textSecondary)
                        // Fixed box so every symbol centers identically
                        // regardless of its intrinsic width/baseline.
                        .frame(width: 22, height: 17)

                    if badgeCount > 0 {
                        Text("\(min(badgeCount, 99))")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(DS.Color.accent)
                            .clipShape(Capsule())
                            .offset(x: 6, y: -4)
                    }
                }

                Text(tab.localizedTitle)
                    .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? DS.Color.accent : DS.Color.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.xs)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                        .fill(DS.Color.accentSubtle)
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
            PDFOutlineView(pdfViewManager: pdfViewManager)
        case .annotations:
            AnnotationsView(
                bookmarkStore:   bookmarkStore,
                highlightStore:  highlightStore,
                noteStore:       noteStore,
                savedWordsStore: savedWordsStore,
                pdfViewManager:  pdfViewManager,
                currentFilename: currentDocumentName
            )
        case .words:
            WordsView(
                store: savedWordsStore,
                currentDocumentName: currentDocumentName
            )
        }
    }
}
