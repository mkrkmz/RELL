//
//  LibraryView.swift
//  Reader for Language Learner
//
//  Cover-grid view of every document in the reading history. Reached from
//  the dashboard's "View all"; supports search, sorting, opening, and
//  removing entries from the library.
//

import AppKit
import SwiftUI

struct LibraryView: View {
    let documents: [RecentDocument]
    var coverStore: DocumentCoverStore?
    var onOpen: ((RecentDocument) -> Void)?
    var onRemove: ((RecentDocument) -> Void)?
    var statsProvider: ((RecentDocument) -> DocumentStats)? = nil
    let onBack: () -> Void

    @Environment(RecentDocumentStore.self) private var recentDocumentStore
    @Environment(\.openWindow) private var openWindow

    @State private var searchText = ""
    @State private var statsDocument: RecentDocument?
    @State private var activeFilter: LibraryFilter = .all
    @State private var pendingCollectionAssignment: RecentDocument?
    @State private var newCollectionName = ""
    @State private var showingManageCollections = false
    @AppStorage(StorageKey.librarySortOrder) private var sortOrderRaw: String = LibrarySortOrder.lastOpened.rawValue
    @AppStorage(StorageKey.libraryViewStyle) private var viewStyleRaw: String = LibraryCard.Style.grid.rawValue
    private var viewStyle: LibraryCard.Style { LibraryCard.Style(rawValue: viewStyleRaw) ?? .grid }
    @FocusState private var searchFocused: Bool

    private var sortOrder: LibrarySortOrder {
        LibrarySortOrder(rawValue: sortOrderRaw) ?? .lastOpened
    }

    private var filteredDocuments: [RecentDocument] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var matching = trimmed.isEmpty
            ? documents
            : documents.filter { $0.filename.localizedCaseInsensitiveContains(trimmed) }

        switch activeFilter {
        case .all: break
        case .pinned: matching = matching.filter(\.isPinned)
        case .pdf: matching = matching.filter { !$0.isEPUB }
        case .epub: matching = matching.filter { $0.isEPUB && $0.shelf == .books }
        case .articles: matching = matching.filter { $0.shelf == .articles }
        case .stories: matching = matching.filter { $0.shelf == .stories }
        case .collection(let id): matching = matching.filter { $0.collectionID == id }
        }

        let sorted: [RecentDocument]
        switch sortOrder {
        case .lastOpened:
            sorted = matching.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
        case .name:
            sorted = matching.sorted {
                $0.filename.localizedCaseInsensitiveCompare($1.filename) == .orderedAscending
            }
        case .progress:
            sorted = matching.sorted {
                ($0.readingProgress ?? 0) > ($1.readingProgress ?? 0)
            }
        }
        // Pinned documents float to the top of any sort order; Swift's sort
        // is stable, so relative order within each group is preserved.
        return sorted.sorted { $0.isPinned && !$1.isPinned }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            header
            filterChips

            if filteredDocuments.isEmpty {
                emptyResult
            } else if viewStyle == .list {
                LazyVStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    ForEach(filteredDocuments) { document in
                        card(for: document, style: .list)
                    }
                }
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: DS.Spacing.lg)],
                    alignment: .leading,
                    spacing: DS.Spacing.lg
                ) {
                    ForEach(filteredDocuments) { document in
                        card(for: document, style: .grid)
                    }
                }
            }
        }
        .task(id: filteredDocuments.map(\.path)) {
            for document in filteredDocuments {
                coverStore?.requestCover(for: document.path)
            }
        }
        .sheet(item: $statsDocument) { document in
            if let stats = statsProvider?(document) {
                DocumentStatsSheet(document: document, stats: stats)
            }
        }
        .sheet(isPresented: $showingManageCollections) {
            ManageCollectionsSheet(store: recentDocumentStore)
        }
        .onChange(of: recentDocumentStore.collections) { _, collections in
            // A deleted collection's chip disappears — if it was the active
            // filter, fall back to All instead of showing a stuck empty grid.
            if case .collection(let id) = activeFilter, !collections.contains(where: { $0.id == id }) {
                activeFilter = .all
            }
        }
        .alert(
            "New Collection", isPresented: Binding(
                get: { pendingCollectionAssignment != nil },
                set: { if !$0 { pendingCollectionAssignment = nil } }
            ), presenting: pendingCollectionAssignment
        ) { document in
            TextField("Name", text: $newCollectionName)
            Button("Create") {
                let collection = recentDocumentStore.createCollection(name: newCollectionName)
                recentDocumentStore.assign(id: document.id, to: collection.id)
                newCollectionName = ""
            }
            Button("Cancel", role: .cancel) { newCollectionName = "" }
        } message: { _ in
            Text("Name this collection.")
        }
    }

    /// Reads `revision` so the grid re-renders as covers finish loading.
    private func cover(for document: RecentDocument) -> NSImage? {
        guard let coverStore else { return nil }
        _ = coverStore.revision
        return coverStore.cover(for: document.path)
    }

    private func card(for document: RecentDocument, style: LibraryCard.Style) -> some View {
        LibraryCard(
            document: document,
            style: style,
            cover: cover(for: document),
            savedWords: statsProvider?(document).savedWords,
            dueWords: statsProvider?(document).dueWords,
            onShowWords: { WordNotebook.open(onBookNamed: document.filename) { openWindow(id: $0) } },
            collections: recentDocumentStore.collections,
            onOpen: onOpen.map { open in { open(document) } },
            onRemove: onRemove.map { remove in { remove(document) } },
            onShowStats: statsProvider != nil ? { statsDocument = document } : nil,
            onTogglePin: { recentDocumentStore.setPinned(!document.isPinned, id: document.id) },
            onAssignToCollection: { recentDocumentStore.assign(id: document.id, to: $0) },
            onRequestNewCollection: { pendingCollectionAssignment = document },
            onManageCollections: { showingManageCollections = true }
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DS.Spacing.md) {
            Button(action: onBack) {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .keyboardShortcut(.escape, modifiers: [])
            .help("Back to Home (Esc)")

            Text(documents.count == 1 ? "Library · 1 document" : "Library · \(documents.count) documents")
                .font(DS.Typography.headline)
                .foregroundStyle(DS.Color.textPrimary)
                .lineLimit(1)

            Spacer(minLength: DS.Spacing.md)

            ZStack {
                searchShortcutButton
                DSSearchField(text: $searchText, focused: $searchFocused)
                    .frame(width: 180)
                    .help("Search the library (⇧⌘F)")
            }

            Picker("View", selection: $viewStyleRaw) {
                Image(systemName: "square.grid.2x2").tag(LibraryCard.Style.grid.rawValue)
                    .accessibilityLabel("Covers")
                Image(systemName: "list.bullet").tag(LibraryCard.Style.list.rawValue)
                    .accessibilityLabel("List")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Show covers or a list")

            Picker("Sort", selection: $sortOrderRaw) {
                ForEach(LibrarySortOrder.allCases) { order in
                    Text(order.label).tag(order.rawValue)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 130)
            .labelsHidden()
            .help("Sort the library")
        }
    }

    /// Invisible button that keeps ⇧⌘F focusing the search field regardless
    /// of what currently has focus — a plain `.keyboardShortcut` on
    /// `DSSearchField` itself would have no default action to trigger.
    private var searchShortcutButton: some View {
        Button { searchFocused = true } label: { Color.clear }
            .frame(width: 0, height: 0)
            .opacity(0)
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .accessibilityHidden(true)
    }

    /// Says why the shelf is empty and offers the one thing that fills it
    /// (v14 S3).
    @ViewBuilder
    private var emptyResult: some View {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            DSEmptyState(
                icon: "magnifyingglass",
                title: "No Results",
                message: "No documents match \u{201C}\(searchText)\u{201D}.",
                action: { searchText = "" },
                actionLabel: "Clear Search"
            )
        } else if activeFilter == .articles {
            DSEmptyState(
                icon: "globe",
                title: "No Articles Yet",
                message: "Import a web page and read it here like a book.",
                action: { NotificationCenter.default.post(name: .importWebArticleCommand, object: nil) },
                actionLabel: "Import Web Article…"
            )
        } else if activeFilter == .stories {
            DSEmptyState(
                icon: "text.book.closed",
                title: "No Stories Yet",
                message: "RELL can write a short story with the words you're learning.",
                action: { NotificationCenter.default.post(name: .wordStoryCommand, object: nil) },
                actionLabel: "Story From Your Words…"
            )
        } else {
            DSEmptyState(
                icon: "books.vertical",
                title: "Nothing Here",
                message: "No documents on this shelf.",
                action: { activeFilter = .all },
                actionLabel: "Show All"
            )
        }
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.xs) {
                filterChip(.all, title: String(localized: "All"), systemImage: nil)
                filterChip(.pinned, title: String(localized: "Pinned"), systemImage: "pin.fill")
                filterChip(.epub, title: String(localized: "Books"), systemImage: nil)
                filterChip(.pdf, title: String(localized: "PDFs"), systemImage: nil)
                filterChip(.articles, title: String(localized: "Articles"), systemImage: "globe")
                filterChip(.stories, title: String(localized: "Stories"), systemImage: "text.book.closed")
                ForEach(recentDocumentStore.collections) { collection in
                    filterChip(.collection(collection.id), title: collection.name, systemImage: "folder")
                }
            }
        }
    }

    /// `title` stays a String: the call sites pass `String(localized:)` or a
    /// collection's own name, both of which are already resolved.
    private func filterChip(_ filter: LibraryFilter, title: String, systemImage: String?) -> some View {
        let isActive = activeFilter == filter
        return Button {
            activeFilter = filter
        } label: {
            HStack(spacing: DS.Spacing.xxs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(DS.Typography.icon(10, weight: .medium))
                }
                Text(title)
                    .font(DS.Typography.caption.weight(.medium))
            }
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.xxs)
            .background(isActive ? DS.Color.accent : DS.Color.surfaceElevated)
            .foregroundStyle(isActive ? .white : DS.Color.textSecondary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Library grid filter — `.all` shows everything; the rest narrow by pin
/// state, format, or a single collection membership.
enum LibraryFilter: Hashable {
    case all
    case pinned
    case pdf
    /// Books: EPUBs you opened, not articles or stories RELL made.
    case epub
    case articles
    case stories
    case collection(UUID)
}

enum LibrarySortOrder: String, CaseIterable, Identifiable {
    case lastOpened
    case name
    case progress

    var id: String { rawValue }

    /// Raw values back `@AppStorage` — keep them stable; the picker shows this.
    var label: String {
        switch self {
        case .lastOpened: return String(localized: "Last opened")
        case .name:       return String(localized: "Name")
        case .progress:   return String(localized: "Progress")
        }
    }
}


// MARK: - Shelves

/// Which shelf a document sits on (v14 S3): articles and stories are the
/// EPUBs RELL writes into its own Articles and Stories folders.
enum LibraryShelf {
    case books, articles, stories

    func localizedKind(isEPUB: Bool) -> String {
        switch self {
        case .articles: return String(localized: "Article")
        case .stories:  return String(localized: "Story")
        case .books:    return isEPUB ? "EPUB" : "PDF"
        }
    }

    fileprivate static let articlesPath = folderPath(ArticleImporter.folderName)
    fileprivate static let storiesPath = folderPath(WordStory.folderName)

    private static func folderPath(_ name: String) -> String? {
        guard let base = FileManager.default.rellAppSupportDirectory() else { return nil }
        return base.appendingPathComponent(name, isDirectory: true).standardizedFileURL.path + "/"
    }
}

extension RecentDocument {
    var shelf: LibraryShelf {
        let path = URL(fileURLWithPath: self.path).standardizedFileURL.path
        if let articles = LibraryShelf.articlesPath, path.hasPrefix(articles) { return .articles }
        if let stories = LibraryShelf.storiesPath, path.hasPrefix(stories) { return .stories }
        return .books
    }
}
