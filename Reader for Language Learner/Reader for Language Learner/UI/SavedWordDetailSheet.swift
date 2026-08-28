//
//  SavedWordDetailSheet.swift
//  Reader for Language Learner
//
//  The saved-word inspector sheet. Split out of `SavedWordsListView`
//  (v10 Sprint 4, T3).
//

import SwiftUI

struct SavedWordDetailSheet: View {
    @State var word: SavedWord
    var store: SavedWordsStore
    @Environment(\.dismiss) private var dismiss

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "star.fill")
                    .foregroundStyle(DS.Color.star)
                Text(word.term)
                    .font(DS.Typography.headline)
                    .foregroundStyle(DS.Color.textPrimary)
                Spacer()
                Button("", systemImage: "xmark.circle.fill") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(DS.Color.textTertiary)
            }
            .padding(DS.Spacing.lg)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    metadataSection

                    Divider()

                    // Tags editor
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text("TAGS / DECKS").dsOverlineLabel()
                        TagEditorView(tags: $word.tags, suggestions: store.allTags)
                    }

                    Divider()

                    // Notes editor
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text("NOTES").dsOverlineLabel()
                        TextEditor(text: $word.notes)
                            .font(DS.Typography.callout)
                            .frame(minHeight: 64, maxHeight: 120)
                            .scrollContentBackground(.hidden)
                            .padding(DS.Spacing.sm)
                            .background(DS.Color.surfaceInset)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
                    }

                    // LLM output cards
                    if !word.llmOutputs.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                            Text("SAVED OUTPUTS").dsOverlineLabel()
                            ForEach(ModuleType.allCases.filter { word.llmOutputs[$0.rawValue] != nil }) { module in
                                let value = word.llmOutputs[module.rawValue] ?? ""
                                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                                    HStack(spacing: DS.Spacing.xs) {
                                        Circle()
                                            .fill(module.accentColor)
                                            .frame(width: 5, height: 5)
                                        Text(module.title)
                                            .font(DS.Typography.caption.weight(.semibold))
                                            .foregroundStyle(DS.Color.textSecondary)
                                    }
                                    Text(value.trimmingCharacters(in: .whitespacesAndNewlines))
                                        .font(DS.Typography.caption)
                                        .foregroundStyle(DS.Color.textPrimary)
                                        .textSelection(.enabled)
                                }
                                .padding(DS.Spacing.sm)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(DS.Color.surfaceInset)
                                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
                            }
                        }
                    }
                }
                .padding(DS.Spacing.lg)
            }

            Divider()

            // Footer
            HStack {
                Button("Delete", role: .destructive) {
                    store.delete(word); dismiss()
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { store.update(word); dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(DS.Spacing.lg)
        }
        .frame(width: 420, height: 540)
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text("METADATA").dsOverlineLabel()

            if let pdf = word.pdfFilename {
                metaRow("Source", value: pdf + (word.pageNumber.map { " · p.\($0)" } ?? ""))
            }
            metaRow("Mode",   value: word.mode)
            metaRow("Domain", value: word.domain)
            metaRow("Saved",  value: Self.dateFormatter.string(from: word.savedAt))
            metaRow("Status", value: word.reviewStatus.label)
            metaRow("Reviews", value: "\(word.reviewCount)")
            metaRow("Incorrect", value: "\(word.incorrectCount)")
            if let lastReviewedAt = word.lastReviewedAt {
                metaRow("Reviewed", value: Self.dateFormatter.string(from: lastReviewedAt))
            }
            if let nextReviewAt = word.nextReviewAt {
                metaRow("Next", value: Self.dateFormatter.string(from: nextReviewAt))
            }

            if !word.sentence.isEmpty {
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text("Context")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                    Text(word.sentence)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textPrimary)
                        .textSelection(.enabled)
                        .italic()
                }
            }
        }
    }

    private func metaRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            Text(label)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.textTertiary)
                .frame(width: 52, alignment: .trailing)
            Text(value)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.textPrimary)
                .textSelection(.enabled)
        }
    }
}
