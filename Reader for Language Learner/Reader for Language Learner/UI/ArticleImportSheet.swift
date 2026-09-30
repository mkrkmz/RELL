//
//  ArticleImportSheet.swift
//  Reader for Language Learner
//
//  File ▸ Import Web Article… (Roadmap v13 Sprint 4).
//

import SwiftUI

struct ArticleImportSheet: View {
    let onImported: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var isImporting = false
    @State private var failure: String?

    private var url: URL? { ArticleImporter.webURL(from: address) }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text("Import a Web Article")
                    .font(DS.Typography.headline)
                Text("RELL keeps the article's text and opens it as a book — hover, save and review work as usual.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextField("https://…", text: $address)
                .textFieldStyle(.roundedBorder)
                .onSubmit { start() }
                .disabled(isImporting)

            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if isImporting {
                    ProgressView().controlSize(.small)
                    Text("Importing…")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Import") { start() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(url == nil || isImporting)
            }
        }
        .padding(DS.Spacing.lg)
        .frame(width: 460)
        .onAppear {
            // A link already on the clipboard is the likely one.
            if let copied = NSPasteboard.general.string(forType: .string),
               ArticleImporter.webURL(from: copied) != nil, copied.hasPrefix("http") {
                address = copied.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    private func start() {
        guard let url, !isImporting else { return }
        isImporting = true
        failure = nil
        Task {
            do {
                let book = try await ArticleImporter.importArticle(from: url)
                dismiss()
                onImported(book)
            } catch {
                failure = error.localizedDescription
            }
            isImporting = false
        }
    }
}
