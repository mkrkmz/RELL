//
//  SidebarView.swift
//  Reader for Language Learner
//

import PDFKit
import SwiftUI

// MARK: - Sidebar Tab

enum SidebarTab: String, CaseIterable, Identifiable {
    case thumbnails = "Pages"
    case outline    = "Contents"
    case bookmarks  = "Marks"
    case saved      = "Saved"
    case quiz       = "Quiz"
    case stats      = "Stats"
    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .thumbnails: return "square.grid.2x2"
        case .outline:    return "list.bullet.indent"
        case .bookmarks:  return "bookmark"
        case .saved:      return "star"
        case .quiz:       return "brain.head.profile"
        case .stats:      return "chart.bar"
        }
    }
}

// MARK: - SidebarView

struct SidebarView: View {
    var pdfViewManager:  PDFViewManager
    var savedWordsStore: SavedWordsStore
    var bookmarkStore:   PDFBookmarkStore
    var sessionStore:    ReadingSessionStore
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
        .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
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
        return Button {
            withAnimation(DS.Animation.springFast) { selectedTab = tab }
        } label: {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: isSelected
                          ? tab.iconName + ".fill"
                          : tab.iconName)
                        .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? DS.Color.accent : DS.Color.textSecondary)

                    // Badge for Saved / Bookmarks count
                    let badgeCount: Int = {
                        switch tab {
                        case .saved:      return savedWordsStore.words.count
                        case .quiz:       return savedWordsStore.pendingReviewCount
                        case .bookmarks:
                            if let name = currentDocumentName {
                                return bookmarkStore.bookmarks(for: name).count
                            }
                            return 0
                        default: return 0
                        }
                    }()
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

                Text(tab.rawValue)
                    .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? DS.Color.accent : DS.Color.textTertiary)
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
        .accessibilityLabel(tab.rawValue)
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityHint("Switch to \(tab.rawValue) tab")
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
                PDFThumbnailSidebarView(pdfViewManager: pdfViewManager, thumbnailSize: thumbnailSize)
            }
        case .outline:
            PDFOutlineView(pdfViewManager: pdfViewManager)
        case .bookmarks:
            PDFBookmarksView(
                bookmarkStore:   bookmarkStore,
                pdfViewManager:  pdfViewManager,
                currentFilename: currentDocumentName
            )
        case .saved:
            SavedWordsListView(
                store: savedWordsStore,
                currentDocumentName: currentDocumentName
            )
        case .quiz:
            QuizView(store: savedWordsStore)
        case .stats:
            ReadingStatsView(
                sessionStore: sessionStore,
                savedWordsStore: savedWordsStore
            )
        }
    }
}
