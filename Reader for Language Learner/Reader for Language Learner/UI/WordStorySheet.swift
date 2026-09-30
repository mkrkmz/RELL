//
//  WordStorySheet.swift
//  Reader for Language Learner
//
//  "A story from your words" (Roadmap v13 Sprint 4): the words due for
//  review, woven into a short story at the reader's level and opened as a
//  book. Reading it is practice; the review schedule is untouched.
//

import SwiftUI

struct WordStorySheet: View {
    let onOpen: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(SavedWordsStore.self) private var savedWordsStore

    @State private var words: [String] = []
    @State private var isWriting = false
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text("A Story From Your Words")
                    .font(DS.Typography.headline)
                Text("A short story at your level that uses the words you're due to review. It opens as a book; reading it doesn't change when they come up again.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if words.count < WordStory.minimumWords {
                Text("Save a few more words first — a story needs at least \(WordStory.minimumWords).")
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Color.textSecondary)
            } else {
                Text(words.joined(separator: " · "))
                    .font(DS.Typography.callout.weight(.medium))
                    .foregroundStyle(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(DS.Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DS.Color.surfaceInset)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
            }

            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.danger)
            }

            HStack {
                if isWriting {
                    ProgressView().controlSize(.small)
                    Text("Writing your story…")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Write Story") { write() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(words.count < WordStory.minimumWords || isWriting)
            }
        }
        .padding(DS.Spacing.lg)
        .frame(width: 480)
        .onAppear { words = Self.pickWords(from: savedWordsStore) }
    }

    /// Due words first, then the rest of the review queue, in the study
    /// language — the ones reading would do most good for.
    static func pickWords(from store: SavedWordsStore) -> [String] {
        let target = Language.storedTarget.rawValue
        var seen: Set<String> = []
        return (store.dueWords() + store.reviewQueue(includeAll: true))
            .filter { $0.language == nil || $0.language == target }
            .map { $0.term.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            .prefix(WordStory.maximumWords)
            .map { $0 }
    }

    private func write() {
        isWriting = true
        failure = nil
        let target = Language.storedTarget
        let chosen = words
        Task {
            do {
                let raw = try await AppleOnDevice.chatWithFallback(
                    system: WordStory.systemPrompt(target: target, level: CEFRLevel.storedLearnerLevel),
                    user: WordStory.userPrompt(words: chosen),
                    temperature: 0.8,
                    maxTokens: WordStory.maxTokens
                )
                guard let story = WordStory.parse(raw) else {
                    failure = String(localized: "The AI's story couldn't be read. Try again.")
                    isWriting = false
                    return
                }
                let used = WordStory.usedWords(chosen, in: story, language: target)
                let book = try save(story, words: chosen, used: used, language: target)
                dismiss()
                onOpen(book)
            } catch {
                failure = error.localizedDescription
            }
            isWriting = false
        }
    }

    private func save(_ story: WordStory.Story, words: [String], used: [String], language: Language) throws -> URL {
        guard let base = FileManager.default.rellAppSupportDirectory() else { throw CocoaError(.fileNoSuchFile) }
        let folder = base.appendingPathComponent("Stories", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let missing = words.filter { !used.contains($0) }
        let note = missing.isEmpty
            ? String(localized: "Written for you from \(words.count) of your words.")
            : String(localized: "Written for you from your words. Not used: \(missing.joined(separator: ", ")).")
        let book = MiniEPUB.build(
            title: story.title,
            author: "RELL",
            language: language.shortCode.lowercased(),
            chapters: [.init(title: story.title, blocks: story.paragraphs.map { .init(text: $0, isHeading: false) })],
            note: note
        )
        let destination = ArticleImporter.uniqueFile(named: MiniEPUB.fileName(for: story.title), in: folder)
        try book.write(to: destination, options: .atomic)
        return destination
    }
}
