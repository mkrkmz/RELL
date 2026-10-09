//
//  WordsView.swift
//  Reader for Language Learner
//
//  Sidebar container merging the saved-words list and the review session
//  under one tab with a segmented switcher.
//

import SwiftUI

struct WordsView: View {
    var store: SavedWordsStore
    var currentDocumentName: String?
    /// The open book (v16 S1): both segments work on its words.
    var book: SavedWordsListView.BookContext? = nil

    enum Segment: String, CaseIterable, Identifiable {
        case words = "Words"
        case review = "Review"
        var id: String { rawValue }
    }

    @AppStorage(StorageKey.wordsSegment) private var segmentRaw = Segment.words.rawValue
    @Environment(\.openWindow) private var openWindow

    private var segment: Segment {
        Segment(rawValue: segmentRaw) ?? .words
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: Binding(
                get: { segment },
                set: { segmentRaw = $0.rawValue }
            )) {
                Text("Words").tag(Segment.words)
                Text(reviewLabel).tag(Segment.review)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.xs)

            Divider()

            switch segment {
            case .words:
                SavedWordsListView(store: store, currentDocumentName: currentDocumentName, book: book,
                                   onStudyBook: book.map { book in { studyFullScreen(bookPath: book.document.path) } },
                                   onShowAllWords: { WordNotebook.open { openWindow(id: $0) } })
            case .review:
                // Approved v15 S2 decision 3: the quick review stays here;
                // the study room is one click away.
                studyFullScreenButton
                QuizView(store: store, scopeIDs: bookIDs, onStudyAll: { studyFullScreen(bookPath: nil) })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var studyFullScreenButton: some View {
        Button {
            studyFullScreen(bookPath: book?.document.path)
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                Text(book == nil ? String(localized: "Study Full Screen") : String(localized: "Study This Book Full Screen"))
                Spacer(minLength: 0)
                Text("⌥⌘V")
                    .font(DS.Typography.mono)
                    .opacity(0.7)
            }
            .font(DS.Typography.callout.weight(.semibold))
            .foregroundStyle(DS.Color.accent)
            .lineLimit(1)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.xs)
            .background(DS.Color.accentSubtle, in: RoundedRectangle(cornerRadius: DS.Radius.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open the study room in full screen")
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.top, DS.Spacing.sm)
    }

    /// The book's saved words — this file, other copies, Kindle.
    private var bookIDs: Set<UUID>? {
        book.map {
            BookWords(document: $0.document, words: store.words, encounters: [],
                      matchingTitles: BookWords.matchesTitles(forDocumentAt: $0.document.path)).ids
        }
    }

    private func studyFullScreen(bookPath: String?) {
        StudyRoom.openFullScreen(using: openWindow, bookPath: bookPath)
    }

    private var reviewLabel: String {
        let due = bookIDs.map { ids in store.words.count { ids.contains($0.id) && store.isDue($0) } }
            ?? store.pendingReviewCount
        return due > 0
            ? String(localized: "Review (\(due))")
            : String(localized: "Review")
    }
}
