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

    @State private var searchText = ""
    @State private var statsDocument: RecentDocument?
    @State private var activeFilter: LibraryFilter = .all
    @State private var pendingCollectionAssignment: RecentDocument?
    @State private var newCollectionName = ""
    @State private var showingManageCollections = false
    @AppStorage("librarySortOrder") private var sortOrderRaw: String = LibrarySortOrder.lastOpened.rawValue
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
        case .epub: matching = matching.filter(\.isEPUB)
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
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: DS.Spacing.lg)],
                    alignment: .leading,
                    spacing: DS.Spacing.lg
                ) {
                    ForEach(filteredDocuments) { document in
                        LibraryCard(
                            document: document,
                            cover: cover(for: document),
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

    private var emptyResult: some View {
        DSEmptyState(
            icon: "magnifyingglass",
            title: "No Results",
            message: "No documents match \u{201C}\(searchText)\u{201D}."
        )
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.xs) {
                filterChip(.all, title: String(localized: "All"), systemImage: nil)
                filterChip(.pinned, title: String(localized: "Pinned"), systemImage: "pin.fill")
                filterChip(.pdf, title: "PDF", systemImage: nil)
                filterChip(.epub, title: "EPUB", systemImage: nil)
                ForEach(recentDocumentStore.collections) { collection in
                    filterChip(.collection(collection.id), title: collection.name, systemImage: "folder")
                }
            }
        }
    }

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
    case epub
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

// MARK: - Library Card

private struct LibraryCard: View {
    let document: RecentDocument
    var cover: NSImage?
    var collections: [DocumentCollection] = []
    var onOpen: (() -> Void)?
    var onRemove: (() -> Void)?
    var onShowStats: (() -> Void)?
    var onTogglePin: (() -> Void)?
    var onAssignToCollection: ((UUID?) -> Void)?
    var onRequestNewCollection: (() -> Void)?
    var onManageCollections: (() -> Void)?

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fileExists: Bool {
        FileManager.default.fileExists(atPath: document.path)
    }

    var body: some View {
        Button {
            onOpen?()
        } label: {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                coverArea

                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(displayTitle)
                        .font(DS.Typography.label)
                        .foregroundStyle(fileExists ? DS.Color.textPrimary : DS.Color.textTertiary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(subtitleText)
                        .font(DS.Typography.caption2)
                        .foregroundStyle(DS.Color.textTertiary)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
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
            if let onTogglePin {
                Button(document.isPinned ? "Unpin" : "Pin", systemImage: document.isPinned ? "pin.slash" : "pin", action: onTogglePin)
            }
            if let onAssignToCollection {
                Menu("Add to Collection") {
                    ForEach(collections) { collection in
                        Button {
                            onAssignToCollection(collection.id)
                        } label: {
                            Label(collection.name, systemImage: document.collectionID == collection.id ? "checkmark" : "")
                        }
                    }
                    if !collections.isEmpty { Divider() }
                    if let onRequestNewCollection {
                        Button("New Collection…", action: onRequestNewCollection)
                    }
                }
                if document.collectionID != nil {
                    Button("Remove from Collection") {
                        onAssignToCollection(nil)
                    }
                }
                if let onManageCollections, !collections.isEmpty {
                    Button("Manage Collections…", action: onManageCollections)
                }
            }
            if let onShowStats {
                Divider()
                Button("Document Stats…", action: onShowStats)
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

    private var coverArea: some View {
        ZStack {
            if let cover {
                Image(nsImage: cover)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                DS.Color.accentSubtle
                Image(systemName: fileExists ? "book.pages" : "questionmark.folder")
                    .font(DS.Typography.icon(24, weight: .light))
                    .foregroundStyle(DS.Color.accent.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(3 / 4, contentMode: .fit)
        .overlay(alignment: .topTrailing) {
            if document.isPinned {
                Image(systemName: "pin.fill")
                    .font(DS.Typography.icon(9, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(.black.opacity(0.45), in: Circle())
                    .padding(5)
            }
        }
        .overlay(alignment: .bottom) {
            if let progress = document.readingProgress {
                GeometryReader { geo in
                    Rectangle()
                        .fill(DS.Color.accent.opacity(0.85))
                        .frame(width: geo.size.width * progress)
                }
                .frame(height: 3)
                // DS-exempt: dims directly against the cover photo, which is
                // full-color and theme-independent — a semantic surface
                // token would fight the image instead of sitting under it.
                .background(.black.opacity(0.18))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.sm)
                .strokeBorder(
                    isHovered ? DS.Color.accentMuted : DS.Color.hairlineStrong,
                    lineWidth: isHovered ? 1.2 : 0.7
                )
        )
        .dsShadow(isHovered ? DS.Shadow.card : DS.Shadow.subtle)
        .scaleEffect(isHovered && !reduceMotion ? 1.02 : 1)
        .animation(DS.Animation.standard, value: cover)
    }

    private var displayTitle: String {
        document.displayTitle
    }

    private var subtitleText: String {
        guard fileExists else { return "File not found" }
        var parts: [String] = []
        if document.lastPageIndex != nil {
            parts.append(document.pageLabel)
        }
        parts.append(Self.relativeFormatter.localizedString(for: document.lastOpenedAt, relativeTo: .now))
        return parts.joined(separator: "  ·  ")
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}

// MARK: - Document Stats

struct DocumentStats {
    var readingTime: Double
    var savedWords: Int
    var dueWords: Int
    var notes: Int
    var bookmarks: Int
    var progress: Double?
    var pageLabel: String
}

private struct DocumentStatsSheet: View {
    let document: RecentDocument
    let stats: DocumentStats

    @Environment(\.dismiss) private var dismiss

    private var displayTitle: String {
        document.displayTitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .foregroundStyle(DS.Color.accent)
                Text(displayTitle)
                    .font(DS.Typography.headline)
                    .foregroundStyle(DS.Color.textPrimary)
                    .lineLimit(1)
                Spacer()
                Button("", systemImage: "xmark.circle.fill") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(DS.Color.textTertiary)
            }
            .padding(DS.Spacing.lg)

            Divider()

            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                if let progress = stats.progress {
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        HStack {
                            Text(stats.pageLabel)
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Color.textSecondary)
                            Spacer()
                            Text("\(Int(progress * 100))%")
                                .font(DS.Typography.caption.weight(.semibold))
                                .foregroundStyle(DS.Color.accent)
                        }
                        ProgressView(value: progress).tint(DS.Color.accent)
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DS.Spacing.sm) {
                    statCell(icon: "clock", value: formattedTime, label: "Read", tint: DS.Color.accent)
                    statCell(icon: "star", value: "\(stats.savedWords)", label: "Saved words", tint: .yellow)
                    statCell(icon: "clock.badge.exclamationmark", value: "\(stats.dueWords)", label: "Due", tint: DS.Color.warning)
                    statCell(icon: "note.text", value: "\(stats.notes)", label: "Notes", tint: .purple)
                    statCell(icon: "bookmark", value: "\(stats.bookmarks)", label: "Bookmarks", tint: .purple)
                }
            }
            .padding(DS.Spacing.lg)

            Spacer(minLength: 0)
        }
        .frame(width: 360, height: 360)
    }

    private var formattedTime: String {
        let total = Int(stats.readingTime)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "—"
    }

    private func statCell(icon: String, value: String, label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Image(systemName: icon)
                .font(DS.Typography.icon(13))
                .foregroundStyle(tint)
            Text(value)
                .font(DS.Typography.headline)
                .foregroundStyle(DS.Color.textPrimary)
            Text(label)
                .font(DS.Typography.caption2)
                .foregroundStyle(DS.Color.textTertiary)
        }
        .padding(DS.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
    }
}

// MARK: - Manage Collections

private struct ManageCollectionsSheet: View {
    let store: RecentDocumentStore

    @Environment(\.dismiss) private var dismiss
    @State private var renamingID: UUID?
    @State private var renameText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "folder")
                    .foregroundStyle(DS.Color.accent)
                Text("Manage Collections")
                    .font(DS.Typography.headline)
                    .foregroundStyle(DS.Color.textPrimary)
                Spacer()
                Button("", systemImage: "xmark.circle.fill") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(DS.Color.textTertiary)
            }
            .padding(DS.Spacing.lg)

            Divider()

            if store.collections.isEmpty {
                DSEmptyState(
                    icon: "folder",
                    title: "No Collections",
                    message: "Add a document to a collection to see it here."
                )
                .padding(DS.Spacing.lg)
                Spacer(minLength: 0)
            } else {
                List {
                    ForEach(store.collections) { collection in
                        row(for: collection)
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 340, height: 360)
    }

    @ViewBuilder
    private func row(for collection: DocumentCollection) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            if renamingID == collection.id {
                TextField("Name", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        store.renameCollection(id: collection.id, to: renameText)
                        renamingID = nil
                    }
            } else {
                Text(collection.name)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Color.textPrimary)
                Spacer()
                Button {
                    renameText = collection.name
                    renamingID = collection.id
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .foregroundStyle(DS.Color.textSecondary)
                Button(role: .destructive) {
                    store.deleteCollection(id: collection.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(DS.Color.danger)
            }
        }
        .padding(.vertical, DS.Spacing.xxs)
    }
}
