//
//  WordNotebookView.swift
//  Reader for Language Learner
//
//  The word notebook (Roadmap v16 Sprint 2, approved decision 1): every
//  saved word in its own window, three columns — books, decks and states;
//  the list or a table; the selected word's page, saved as you edit. Opened
//  from the home screen's Tools, ⌘K, the Go menu (⌥⌘K), a book's "All
//  Words…" and Spotlight.
//

import SwiftUI

struct WordNotebookView: View {
    var store: SavedWordsStore

    @Environment(\.openWindow) private var openWindow
    @State private var source: WordNotebook.Source? = .all
    @State private var selection: UUID?
    @State private var showAllBooks = false
    @AppStorage(StorageKey.notebookTableMode) private var tableMode = false
    /// Saved twice (v16 S3) — the tagger over every word, so worked out
    /// when the words change rather than on every redraw.
    @State private var duplicates: [WordMerge.Group] = []

    /// Books shown before "N more books".
    private static let collapsedBookCount = 6

    private var books: [WordNotebook.Book] { WordNotebook.books(from: store.words) }

    var body: some View {
        NavigationSplitView {
            sourceList
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
        } content: {
            Group {
                if source == .duplicates {
                    DuplicateWordsView(store: store, groups: duplicates, selection: $selection,
                                       onMerged: findDuplicates)
                } else {
                    SavedWordsListView(
                        store: store,
                        currentDocumentName: nil,
                        pool: WordNotebook.words(for: source ?? .all, from: store.words),
                        selection: $selection,
                        tableMode: tableMode
                    )
                }
            }
            .navigationSplitViewColumnWidth(min: 320, ideal: 420)
            .toolbar { toolbar }
        } detail: {
            if let selection, let word = store.word(withID: selection) {
                SavedWordDetailSheet(word: word, store: store, isPane: true)
                    .id(selection)
            } else {
                DSEmptyState(icon: "character.book.closed", title: "Choose a word",
                             message: "Its page shows here: the card, how well you remember it and where you met it.")
            }
        }
        .navigationTitle(Text("Word Notebook"))
        .onAppear(perform: takePendingReveal)
        .task(id: store.words.count) { findDuplicates() }
        .onReceive(NotificationCenter.default.publisher(for: .revealInNotebook)) { _ in takePendingReveal() }
    }

    private func findDuplicates() {
        duplicates = WordMerge.duplicates(in: store.words)
    }

    private func takePendingReveal() {
        if let name = WordNotebook.pendingBookName {
            WordNotebook.pendingBookName = nil
            if let book = WordNotebook.book(named: name, in: books) {
                source = .book(book)
                selection = nil
            }
        }
        guard let id = WordNotebook.pendingReveal else { return }
        WordNotebook.pendingReveal = nil
        source = .all
        selection = id
    }

    // MARK: First column

    private var sourceList: some View {
        List(selection: $source) {
            Section {
                row(.all, String(localized: "All Words"), "tray.full", store.words.count)
                row(.waiting, String(localized: "Waiting for Review"), "clock", WordNotebook.words(for: .waiting, from: store.words).count)
                row(.new, String(localized: "Never Studied"), "sparkle", WordNotebook.words(for: .new, from: store.words).count)
                row(.struggling, String(localized: "You Keep Forgetting"), "exclamationmark.arrow.circlepath",
                    WordNotebook.words(for: .struggling, from: store.words).count)
                row(.missingMeaning, String(localized: "Missing a Meaning"), "text.badge.plus",
                    WordNotebook.words(for: .missingMeaning, from: store.words).count)
                if !duplicates.isEmpty || source == .duplicates {
                    row(.duplicates, String(localized: "Saved Twice"), "square.on.square", duplicates.count)
                }
            }
            let books = books
            if !books.isEmpty {
                Section("Books") {
                    let shown = showAllBooks ? books : Array(books.prefix(Self.collapsedBookCount))
                    ForEach(shown) { book in
                        row(.book(book), book.title, "book.closed", book.count)
                    }
                    if books.count > Self.collapsedBookCount {
                        Button(showAllBooks ? String(localized: "Fewer Books")
                                            : String(localized: "\(books.count - Self.collapsedBookCount) More Books")) {
                            withAnimation(DS.Animation.standard) { showAllBooks.toggle() }
                        }
                        .buttonStyle(.link)
                        .font(DS.Typography.caption)
                    }
                    let noBook = WordNotebook.words(for: .noBook, from: store.words).count
                    if noBook > 0 {
                        row(.noBook, String(localized: "No Book"), "questionmark.square.dashed", noBook)
                    }
                }
            }
            if !store.allTags.isEmpty {
                Section("Decks") {
                    ForEach(store.allTags, id: \.self) { tag in
                        row(.deck(tag), tag, "tag", store.tagCount(tag))
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func row(_ value: WordNotebook.Source, _ title: String, _ icon: String, _ count: Int) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: DS.Spacing.xs)
            Text("\(count)")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.textTertiary)
                .monospacedDigit()
        }
        .tag(value)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem {
            Picker("View", selection: $tableMode) {
                Label("List", systemImage: "list.bullet").tag(false)
                Label("Table", systemImage: "tablecells").tag(true)
            }
            .pickerStyle(.segmented)
            .help("Show the words as a list or a table")
        }
        ToolbarItem {
            Button {
                openWindow(id: StudyRoom.windowID)
            } label: {
                Label("Study Room", systemImage: "rectangle.stack")
            }
            .help("Open the study room (⌥⌘V)")
        }
    }
}

// MARK: - Table

/// The notebook's table: sortable by every column (v16 S2).
struct WordTable: View {
    let words: [SavedWord]
    @Binding var selection: UUID?

    nonisolated struct Row: Identifiable, Sendable {
        let id: UUID
        let term: String
        let meaning: String
        let level: String
        let status: String
        let statusOrder: Int
        let nextReview: Date
        let book: String
    }

    @State private var sortOrder = [KeyPathComparator(\Row.term)]

    private var rows: [Row] {
        words.map { word in
            let status = word.reviewStatus
            return Row(
                id: word.id,
                term: word.term,
                meaning: SavedWordRow.oneLineMeaning(of: word).map(MarkdownUtils.sanitizeLLMOutput) ?? "",
                level: word.cefrLevel ?? "",
                status: status.localizedTitle,
                statusOrder: [ReviewStatus.due, .new, .scheduled, .mastered].firstIndex(of: status) ?? 0,
                nextReview: word.nextReviewAt ?? .distantFuture,
                book: word.pdfFilename.map(BookIdentity.displayTitle) ?? ""
            )
        }
        .sorted(using: sortOrder)
    }

    var body: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Word", value: \.term)
            TableColumn("Meaning", value: \.meaning) { Text($0.meaning).foregroundStyle(DS.Color.textSecondary) }
            TableColumn("Level", value: \.level).width(min: 40, ideal: 50, max: 70)
            TableColumn("Status", value: \.statusOrder) { Text($0.status) }.width(min: 70, ideal: 90)
            TableColumn("Next Review", value: \.nextReview) { row in
                if row.nextReview == .distantFuture {
                    Text("—").foregroundStyle(DS.Color.textTertiary)
                } else {
                    Text(row.nextReview, format: .relative(presentation: .named))
                }
            }
            TableColumn("Book", value: \.book) { Text($0.book).foregroundStyle(DS.Color.textSecondary) }
        }
    }
}
