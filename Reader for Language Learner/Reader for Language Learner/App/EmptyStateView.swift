//
//  EmptyStateView.swift
//  Reader for Language Learner
//
//  Extracted from ContentView.swift
//

import SwiftUI

struct EmptyStateView: View {
    let onOpenPDF: () -> Void
    var recentDocuments: [RecentDocument] = []
    var noteStore: PDFNoteStore? = nil
    var savedWordsStore: SavedWordsStore? = nil
    var bookmarkStore: PDFBookmarkStore? = nil
    var onOpenRecent: ((RecentDocument) -> Void)? = nil

    @State private var isHoveringButton = false

    var body: some View {
        ZStack {
            // Subtle radial gradient backdrop
            RadialGradient(
                colors: [DS.Color.accentSubtle, .clear],
                center: .center,
                startRadius: 60,
                endRadius: 320
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Icon badge
                ZStack {
                    Circle()
                        .fill(DS.Color.accentSubtle)
                        .frame(width: 96, height: 96)
                    Circle()
                        .strokeBorder(DS.Color.accentMuted, lineWidth: 1)
                        .frame(width: 96, height: 96)
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 38, weight: .light))
                        .foregroundStyle(DS.Color.accent)
                }
                .dsShadow(DS.Shadow.card)

                Spacer().frame(height: DS.Spacing.xxl)

                // Text block
                VStack(spacing: DS.Spacing.sm) {
                    Text("Open a PDF to start reading")
                        .font(DS.Typography.title)
                        .foregroundStyle(DS.Color.textPrimary)
                    Text("Select a word or sentence while reading\nto look it up instantly with AI.")
                        .font(DS.Typography.subhead)
                        .foregroundStyle(DS.Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }

                Spacer().frame(height: DS.Spacing.xxl)

                // CTA button
                Button(action: onOpenPDF) {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "folder.badge.plus")
                        Text("Open PDF…")
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, DS.Spacing.xl)
                    .padding(.vertical, DS.Spacing.md)
                    .background(DS.Color.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                    .dsShadow(isHoveringButton ? DS.Shadow.float : DS.Shadow.card)
                    .scaleEffect(isHoveringButton ? 1.02 : 1.0)
                    .animation(DS.Animation.springFast, value: isHoveringButton)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("o", modifiers: [.command])
                .onHover { isHoveringButton = $0 }

                Spacer().frame(height: DS.Spacing.lg)

                // Drag hint
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: 11))
                    Text("Or drag a PDF file here")
                        .font(DS.Typography.caption)
                }
                .foregroundStyle(DS.Color.textTertiary)

                if !recentDocuments.isEmpty {
                    Spacer().frame(height: DS.Spacing.xxxl)
                    recentDocumentsSection
                }

                Spacer()
            }
            .padding(.horizontal, DS.Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var recentDocumentsSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack {
                Text("Continue Reading")
                    .font(DS.Typography.headline)
                    .foregroundStyle(DS.Color.textPrimary)
                Spacer()
                Text("\(recentDocuments.count) recent")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220, maximum: 280), spacing: DS.Spacing.md)],
                spacing: DS.Spacing.md
            ) {
                ForEach(recentDocuments.prefix(4)) { document in
                    RecentDocumentCard(
                        document: document,
                        noteCount: noteStore?.count(for: document.filename) ?? 0,
                        savedWordCount: savedWordsStore?.words.filter { $0.pdfFilename == document.filename }.count ?? 0,
                        bookmarkCount: bookmarkStore?.bookmarks(for: document.filename).count ?? 0,
                        onOpen: { onOpenRecent?(document) }
                    )
                }
            }
        }
        .frame(maxWidth: 980)
    }
}

private struct RecentDocumentCard: View {
    let document: RecentDocument
    let noteCount: Int
    let savedWordCount: Int
    let bookmarkCount: Int
    let onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text(document.filename)
                            .font(DS.Typography.label)
                            .foregroundStyle(DS.Color.textPrimary)
                            .lineLimit(2)
                        Text(document.lastOpenedAt, style: .relative)
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Color.textTertiary)
                    }
                    Spacer()
                    Label(document.pageLabel, systemImage: "book.pages")
                        .font(DS.Typography.caption.weight(.semibold))
                        .foregroundStyle(DS.Color.accent)
                }

                HStack(spacing: DS.Spacing.sm) {
                    statPill(icon: "note.text", text: "\(noteCount) notes")
                    statPill(icon: "star", text: "\(savedWordCount) saved")
                    statPill(icon: "bookmark", text: "\(bookmarkCount)")
                }

                Text(document.url.lastPathComponent)
                    .font(DS.Typography.caption2)
                    .foregroundStyle(DS.Color.textTertiary)
                    .lineLimit(1)
            }
            .padding(DS.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovered ? DS.Color.accentSubtle : DS.Color.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .strokeBorder(isHovered ? DS.Color.accentMuted : DS.Color.separator, lineWidth: 1)
            )
            .dsShadow(isHovered ? DS.Shadow.float : DS.Shadow.card)
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            .animation(DS.Animation.springFast, value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private func statPill(icon: String, text: String) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: icon)
            Text(text)
        }
        .font(DS.Typography.caption2.weight(.medium))
        .foregroundStyle(DS.Color.textSecondary)
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, 5)
        .background(DS.Color.surfaceInset)
        .clipShape(Capsule())
    }
}
