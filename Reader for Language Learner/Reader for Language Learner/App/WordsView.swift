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

    enum Segment: String, CaseIterable, Identifiable {
        case words = "Words"
        case review = "Review"
        var id: String { rawValue }
    }

    @AppStorage("wordsSegment") private var segmentRaw = Segment.words.rawValue

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
                SavedWordsListView(store: store, currentDocumentName: currentDocumentName)
            case .review:
                QuizView(store: store)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var reviewLabel: String {
        let due = store.pendingReviewCount
        return due > 0 ? "Review (\(due))" : "Review"
    }
}
