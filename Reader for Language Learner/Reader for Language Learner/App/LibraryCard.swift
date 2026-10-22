//
//  LibraryCard.swift
//  Reader for Language Learner
//
//  A document's card in the library, as a grid tile or a list row. Split
//  out of LibraryView.swift (v20 S0), unchanged.
//

import AppKit
import SwiftUI

// MARK: - Library Card

struct LibraryCard: View {
    enum Style: String { case grid, list }

    let document: RecentDocument
    var style: Style = .grid
    var cover: NSImage?
    /// Saved words from this book — copies and Kindle included (v16 S3).
    var savedWords: Int? = nil
    var dueWords: Int? = nil
    /// Opens the word notebook on this book.
    var onShowWords: (() -> Void)? = nil
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
            if style == .list {
                listLabel
            } else {
                gridLabel
            }
        }
        .buttonStyle(.plain)
        .disabled(onOpen == nil || !fileExists)
        .opacity(fileExists ? 1 : 0.55)
        .animation(DS.Animation.fast, value: isHovered)
        .onHover { isHovered = $0 }
        .contextMenu { documentMenu }

        .accessibilityLabel("Open \(displayTitle), \(document.pageLabel)")
    }

    // MARK: List style (v14 S3)

    private var listLabel: some View {
        HStack(spacing: DS.Spacing.md) {
            Group {
                if let cover {
                    Image(nsImage: cover).resizable().aspectRatio(contentMode: .fill)
                } else {
                    DS.Color.surfaceInset
                        .overlay(Image(systemName: document.isEPUB ? "book" : "doc.text").foregroundStyle(DS.Color.textTertiary))
                }
            }
            .frame(width: DS.Layout.coverMini.width, height: DS.Layout.coverMini.height)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xs))

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: DS.Spacing.xs) {
                    if document.isPinned {
                        Image(systemName: "pin.fill")
                            .font(DS.Typography.icon(9, weight: .semibold))
                            .foregroundStyle(DS.Color.textTertiary)
                    }
                    Text(displayTitle)
                        .font(DS.Typography.label)
                        .foregroundStyle(fileExists ? DS.Color.textPrimary : DS.Color.textTertiary)
                        .lineLimit(1)
                }
                Text(listSubtitle)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: DS.Spacing.md)

            if let coverage = document.coverage?.profile, coverage.totalTokens > 0 {
                CoverageBadge(profile: coverage)
            }
            if let progress = document.readingProgress {
                Text("\(Int((progress * 100).rounded()))%")
                    .font(DS.Typography.caption)
                    .monospacedDigit()
                    .foregroundStyle(DS.Color.textSecondary)
                    .frame(width: 40, alignment: .trailing)
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
        .background(isHovered ? DS.Color.hoverOverlay : DS.Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
    }

    /// Kind · where you are · saved words.
    private var listSubtitle: String {
        guard fileExists else { return String(localized: "File not found") }
        var parts: [String] = [document.shelf.localizedKind(isEPUB: document.isEPUB)]
        if document.lastPageIndex != nil { parts.append(document.pageLabel) }
        if let savedWords, savedWords > 0 {
            // Copies and Kindle included (v16 S3); the context menu opens them.
            parts.append(String(localized: "\(savedWords) words"))
        }
        return parts.joined(separator: " · ")
    }

    /// "232 · 9" on the cover's corner — saved words and the ones waiting;
    /// a click opens the word notebook on the book (v16 S3). On the cover,
    /// in the coverage badge's dark style, so it reads on any picture and
    /// never covers the title (live pass).
    @ViewBuilder
    private var wordsBadge: some View {
        if let savedWords, savedWords > 0, let onShowWords {
            HStack(spacing: DS.Spacing.xxs + DS.Spacing.hairline) {
                Image(systemName: "character.book.closed")
                Text("\(savedWords)")
                if let dueWords, dueWords > 0 {
                    Text("· \(dueWords)").foregroundStyle(DS.Color.warning)
                }
            }
            .font(DS.Typography.caption2.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, DS.Spacing.xs + DS.Spacing.xxs)
            .padding(.vertical, DS.Spacing.xxs)
            // DS-exempt: sits on the full-color cover photo, like CoverageBadge.
            .background(.black.opacity(0.6), in: Capsule())
            .padding(.trailing, DS.Spacing.xs + DS.Spacing.hairline)
            .padding(.bottom, DS.Spacing.sm + DS.Spacing.hairline)   // clear of the reading-progress bar
            .contentShape(Capsule())
            // Over the card's own click: the badge opens the words.
            .highPriorityGesture(TapGesture().onEnded { onShowWords() })
            .help("Show this book's words in the word notebook")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(savedWords) words from this book"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onShowWords() }
        }
    }

    // MARK: Grid style

    private var gridLabel: some View {
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

    @ViewBuilder
    private var documentMenu: some View {
            if let onOpen {
                Button("Open", action: onOpen)
                    .disabled(!fileExists)
                if let onShowWords, (savedWords ?? 0) > 0 {
                    Button("Show This Book's Words", action: onShowWords)
                }
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

    private var coverArea: some View {
        ZStack {
            if let cover {
                Image(nsImage: cover)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                DSCoverPlaceholder(iconSize: 24, fileExists: fileExists)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(3 / 4, contentMode: .fit)
        .overlay(alignment: .topTrailing) {
            if document.isPinned {
                Image(systemName: "pin.fill")
                    .font(DS.Typography.icon(9, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(DS.Spacing.xs + DS.Spacing.hairline)
                    .background(.black.opacity(0.45), in: Circle())
                    .padding(DS.Spacing.xs + DS.Spacing.hairline)
            }
        }
        .overlay(alignment: .topLeading) {
            // How much of this book you already know — the number that
            // decides whether it's worth starting (L-V2).
            if let coverage = document.coverage?.profile, coverage.totalTokens > 0 {
                CoverageBadge(profile: coverage, filled: true)
                    .padding(DS.Spacing.xs + DS.Spacing.hairline)
            }
        }
        .overlay(alignment: .bottomTrailing) { wordsBadge }
        .overlay(alignment: .bottom) {
            if let progress = document.readingProgress {
                // DS-exempt track: dims directly against the cover photo,
                // which is full-color and theme-independent — a semantic
                // surface token would fight the image.
                DSProgressBar(value: progress, track: .black.opacity(0.18))
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
        .dsShadow(isHovered ? DS.Shadow.float : DS.Shadow.subtle)
        .scaleEffect(isHovered && !reduceMotion ? 1.02 : 1)
        .animation(DS.Animation.standard, value: cover)
    }

    private var displayTitle: String {
        document.displayTitle
    }

    /// Pre-formatted so the sentence around it stays a one-argument string.
    private func percentText(_ profile: LexicalProfile) -> String {
        "\(Int(profile.knownShare * 100))%"
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
