//
//  EPUBOutlineView.swift
//  Reader for Language Learner
//
//  Table of contents for the sidebar's Contents tab when an EPUB is open —
//  the EPUB counterpart of PDFOutlineView.
//

import SwiftUI

struct EPUBOutlineView: View {
    var manager: EPUBViewManager

    var body: some View {
        if manager.tocEntries.isEmpty {
            VStack(spacing: DS.Spacing.sm) {
                Spacer()
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 24, weight: .ultraLight))
                    .foregroundStyle(DS.Color.textTertiary)
                Text("No table of contents")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(manager.tocEntries) { entry in
                Button {
                    manager.open(tocEntry: entry)
                } label: {
                    HStack(spacing: DS.Spacing.xs) {
                        Text(entry.title)
                            .font(DS.Typography.callout)
                            .foregroundStyle(isCurrent(entry) ? DS.Color.accent : DS.Color.textPrimary)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, CGFloat(entry.depth) * DS.Spacing.md)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(entry.title)
            }
            .listStyle(.sidebar)
        }
    }

    private func isCurrent(_ entry: EPUBTOCEntry) -> Bool {
        guard let path = entry.chapterPath,
              let index = manager.document?.chapterIndex(forPath: path)
        else { return false }
        return index == manager.chapterIndex
    }
}
