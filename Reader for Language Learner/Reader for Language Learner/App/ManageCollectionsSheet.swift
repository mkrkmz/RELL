//
//  ManageCollectionsSheet.swift
//  Reader for Language Learner
//
//  Naming, renaming and removing library collections. Split out of
//  LibraryView.swift (v20 S0), unchanged.
//

import AppKit
import SwiftUI

// MARK: - Manage Collections

struct ManageCollectionsSheet: View {
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
                Button("Close", systemImage: "xmark") { dismiss() }
                    .buttonStyle(.dsIconSecondary)
                    .keyboardShortcut(.cancelAction)
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
                .buttonStyle(.dsIconSecondary)
                .help("Rename collection")
                .accessibilityLabel("Rename collection")
                Button(role: .destructive) {
                    store.deleteCollection(id: collection.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(DSIconButtonStyle(tint: DS.Color.danger))
                .help("Delete collection")
                .accessibilityLabel("Delete collection")
            }
        }
        .padding(.vertical, DS.Spacing.xxs)
    }
}
