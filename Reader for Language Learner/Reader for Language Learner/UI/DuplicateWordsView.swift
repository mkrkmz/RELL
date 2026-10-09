//
//  DuplicateWordsView.swift
//  Reader for Language Learner
//
//  "Saved Twice" in the word notebook (Roadmap v16 Sprint 3): the same
//  word saved under two forms, each group with the one to keep and a Merge
//  that asks first and backs everything up before it changes anything.
//

import SwiftUI

struct DuplicateWordsView: View {
    var store: SavedWordsStore
    let groups: [WordMerge.Group]
    @Binding var selection: UUID?
    var onMerged: () -> Void

    @Environment(WordEncounterStore.self) private var encounterStore: WordEncounterStore?
    /// The word to keep, per group; the preferred one until you pick.
    @State private var keep: [String: UUID] = [:]
    @State private var pending: WordMerge.Group?
    @State private var lastMerged: String?

    var body: some View {
        VStack(spacing: 0) {
            if groups.isEmpty {
                DSEmptyState(icon: "checkmark.circle", title: "No word is saved twice",
                             message: "Words saved under two forms, like “gleam” and “gleaming”, show here.")
            } else {
                List {
                    if let lastMerged {
                        Label(lastMerged, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(DS.Color.success)
                            .font(DS.Typography.caption)
                    }
                    ForEach(groups) { group in
                        Section { groupRows(group) } header: {
                            Text(group.words.map(\.term).joined(separator: " · "))
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible, presenting: pending) { group in
            Button("Merge") { merge(group) }
        } message: { _ in
            Text("Sentences, decks, notes and reviews are kept on one word. A copy of your data is saved in Backups first.")
        }
    }

    @ViewBuilder
    private func groupRows(_ group: WordMerge.Group) -> some View {
        let kept = keep[group.id] ?? group.words[0].id
        ForEach(group.words) { word in
            HStack(spacing: DS.Spacing.sm) {
                Button {
                    keep[group.id] = word.id
                } label: {
                    Image(systemName: word.id == kept ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(word.id == kept ? DS.Color.accent : DS.Color.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Keep this one")
                .accessibilityLabel(Text("Keep \(word.term)"))
                VStack(alignment: .leading, spacing: 0) {
                    Text(word.term).font(DS.Typography.callout.weight(.medium))
                    Text(summary(word))
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture { selection = word.id }
            .listRowBackground(selection == word.id ? DS.Color.accentSubtle : nil)
        }
        HStack {
            Spacer()
            Button(String(localized: "Merge Into “\(group.words.first { $0.id == kept }?.term ?? "")”")) {
                pending = group
            }
            .controlSize(.small)
        }
    }

    private func summary(_ word: SavedWord) -> String {
        var parts: [String] = []
        if let meaning = SavedWordRow.oneLineMeaning(of: word) { parts.append(MarkdownUtils.sanitizeLLMOutput(meaning)) }
        parts.append(word.reviewCount == 1 ? String(localized: "1 review") : String(localized: "\(word.reviewCount) reviews"))
        if let book = word.pdfFilename { parts.append(BookIdentity.displayTitle(book)) }
        return parts.joined(separator: " · ")
    }

    private var confirmTitle: String {
        guard let pending else { return "" }
        let kept = keep[pending.id] ?? pending.words[0].id
        let term = pending.words.first { $0.id == kept }?.term ?? ""
        return String(localized: "Merge into “\(term)”?")
    }

    private func merge(_ group: WordMerge.Group) {
        let keepID = keep[group.id] ?? group.words[0].id
        let others = group.words.map(\.id).filter { $0 != keepID }
        PersistenceBackup.snapshotBeforeChange("merge")
        store.merge(keep: keepID, others: others)
        encounterStore?.reassign(from: Set(others), to: keepID)
        let term = store.word(withID: keepID)?.term ?? ""
        lastMerged = String(localized: "Merged into “\(term)”.")
        selection = keepID
        pending = nil
        onMerged()
    }
}
