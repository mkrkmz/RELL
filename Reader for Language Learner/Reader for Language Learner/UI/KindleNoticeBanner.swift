//
//  KindleNoticeBanner.swift
//  Reader for Language Learner
//
//  "Your Kindle has 12 new words" on the home screen (Roadmap v16 Sprint 3):
//  when a Kindle is connected — at launch or the moment it's plugged in —
//  and it holds words not saved yet, in the language you study. Import
//  opens the usual Kindle sheet; closing it hides the notice until there
//  are more. The Kindle is only read.
//

import AppKit
import SwiftUI

struct KindleNoticeBanner: View {
    var store: SavedWordsStore
    @Environment(WordEnricher.self) private var enricher: WordEnricher?
    @AppStorage(StorageKey.kindleNoticeHiddenAtCount) private var hiddenAtCount = 0
    @State private var newWords = 0
    @State private var showImport = false

    var body: some View {
        Group {
            if newWords > hiddenAtCount {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "books.vertical")
                        .foregroundStyle(DS.Color.accent)
                    Text(newWords == 1 ? String(localized: "Your Kindle has 1 new word")
                                       : String(localized: "Your Kindle has \(newWords) new words"))
                        .font(DS.Typography.callout.weight(.semibold))
                    Spacer(minLength: 0)
                    Button("Import…") { showImport = true }
                        .controlSize(.small)
                    Button("Hide", systemImage: "xmark") { hiddenAtCount = newWords }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .foregroundStyle(DS.Color.textTertiary)
                        .help("Hide until the Kindle has more new words")
                        .accessibilityLabel("Hide until the Kindle has more new words")
                }
                .padding(DS.Spacing.md)
                .background(DS.Color.accentSubtle, in: RoundedRectangle(cornerRadius: DS.Radius.md))
            }
        }
        .task { check() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in check() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in check() }
        .onChange(of: store.words.count) { _, _ in check() }
        .sheet(isPresented: $showImport) {
            KindleImportSheet(store: store, enricher: enricher)
        }
    }

    /// New words on a connected Kindle, as an import would count them.
    private func check() {
        newWords = Self.newWordCount(database: KindleVocabulary.connectedDatabase(), existing: store.words)
        if newWords < hiddenAtCount { hiddenAtCount = newWords }   // imported: a later one shows again
    }

    static func newWordCount(database: URL?, existing: [SavedWord], target: Language = Language.storedTarget) -> Int {
        guard let database, let words = try? KindleVocabulary.read(database) else { return 0 }
        let plan = KindleVocabulary.Plan(words: words, existing: existing, target: target)
        return plan.savedWords(books: Set(plan.books.map(\.id)), includeMastered: false).count
    }
}
