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
    let onBack: () -> Void

    @State private var searchText = ""
    @AppStorage("librarySortOrder") private var sortOrderRaw: String = LibrarySortOrder.lastOpened.rawValue

    private var sortOrder: LibrarySortOrder {
        LibrarySortOrder(rawValue: sortOrderRaw) ?? .lastOpened
    }

    private var filteredDocuments: [RecentDocument] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = trimmed.isEmpty
            ? documents
            : documents.filter { $0.filename.localizedCaseInsensitiveContains(trimmed) }

        switch sortOrder {
        case .lastOpened:
            return matching.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
        case .name:
            return matching.sorted {
                $0.filename.localizedCaseInsensitiveCompare($1.filename) == .orderedAscending
            }
        case .progress:
            return matching.sorted {
                ($0.readingProgress ?? 0) > ($1.readingProgress ?? 0)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            header

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
                            onOpen: onOpen.map { open in { open(document) } },
                            onRemove: onRemove.map { remove in { remove(document) } }
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

            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Color.textTertiary)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(DS.Typography.subhead)
            }
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, 5)
            .frame(width: 180)
            .background(DS.Color.surfaceInset)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .strokeBorder(DS.Color.separator.opacity(0.3), lineWidth: 0.7)
            )

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

    private var emptyResult: some View {
        VStack(spacing: DS.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(DS.Color.textTertiary)
            Text("No documents match \u{201C}\(searchText)\u{201D}")
                .font(DS.Typography.subhead)
                .foregroundStyle(DS.Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.xxxl)
    }
}

enum LibrarySortOrder: String, CaseIterable, Identifiable {
    case lastOpened
    case name
    case progress

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lastOpened: return "Last opened"
        case .name:       return "Name"
        case .progress:   return "Progress"
        }
    }
}

// MARK: - Library Card

private struct LibraryCard: View {
    let document: RecentDocument
    var cover: NSImage?
    var onOpen: (() -> Void)?
    var onRemove: (() -> Void)?

    @State private var isHovered = false

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
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(DS.Color.accent.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(3 / 4, contentMode: .fit)
        .overlay(alignment: .bottom) {
            if let progress = document.readingProgress {
                GeometryReader { geo in
                    Rectangle()
                        .fill(DS.Color.accent.opacity(0.85))
                        .frame(width: geo.size.width * progress)
                }
                .frame(height: 3)
                .background(.black.opacity(0.18))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.sm)
                .strokeBorder(
                    isHovered ? DS.Color.accentMuted : DS.Color.separator.opacity(0.35),
                    lineWidth: isHovered ? 1.2 : 0.7
                )
        )
        .dsShadow(isHovered ? DS.Shadow.card : DS.Shadow.subtle)
        .animation(DS.Animation.standard, value: cover)
    }

    private var displayTitle: String {
        document.filename
            .replacingOccurrences(of: ".pdf", with: "", options: [.caseInsensitive, .anchored, .backwards])
            .replacingOccurrences(of: "_", with: " ")
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
