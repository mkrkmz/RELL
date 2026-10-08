//
//  StudySetupView.swift
//  Reader for Language Learner
//
//  The study room's first screen (Roadmap v15 Sprint 2): today at a glance,
//  then how many words, from where, how many new and how — and Start. The
//  queue itself is `StudyPlan`'s.
//

import SwiftUI

struct StudySetupView: View {
    var store: SavedWordsStore
    /// The book read last, for "This book".
    var lastDocument: RecentDocument?
    let availableModes: [QuizMode]
    @Binding var quizMode: QuizMode
    @Binding var typedAutoGrade: Bool
    /// The words to run, and whether it's practice (schedule unchanged).
    let onStart: ([SavedWord], Bool) -> Void

    @AppStorage(StorageKey.studySessionSize) private var size = 20
    @AppStorage(StorageKey.studyNewLimit) private var newLimit = 5
    @State private var source: StudySource = .all

    private var plan: StudyPlan { StudyPlan(size: size, source: source, newLimit: newLimit) }
    private var queue: [SavedWord] { plan.queue(from: store.words) }
    private var practice: [SavedWord] { plan.practiceQueue(from: store.words) }

    private var bookWordCount: Int {
        guard let lastDocument else { return 0 }
        return StudyPlan.words(in: .book(lastDocument.filename), from: store.words).count
    }

    private var strugglingCount: Int {
        StudyPlan.words(in: .struggling, from: store.words).count
    }

    var body: some View {
        ScrollView(.vertical) {
            HStack(alignment: .top, spacing: DS.Spacing.xl) {
                today
                    .frame(width: 230, alignment: .leading)
                form
                    .frame(maxWidth: 560, alignment: .leading)
            }
            .padding(DS.Spacing.xl)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Today

    private var today: some View {
        let streak = store.reviewStreak().current
        return VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("Today")
                .font(DS.Typography.largeTitle)
            Grid(horizontalSpacing: DS.Spacing.sm, verticalSpacing: DS.Spacing.sm) {
                GridRow {
                    tile("\(StudyPlan.dueReviewCount(in: store.words))", String(localized: "waiting for review"), warn: true)
                    tile("\(StudyPlan.newCount(in: store.words))", String(localized: "never studied"))
                }
                GridRow {
                    tile("\(strugglingCount)", String(localized: "you keep forgetting"))
                    tile(streak == 1 ? String(localized: "1 day") : String(localized: "\(streak) days"),
                         String(localized: "review streak"))
                }
            }
            let tomorrow = StudyPlan.comingDueTomorrow(in: store.words)
            if tomorrow > 0 {
                Text("\(tomorrow) more words come due by tomorrow.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func tile(_ value: String, _ label: String, warn: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(DS.Typography.statNumber(20))
                .foregroundStyle(warn ? DS.Color.warning : DS.Color.textPrimary)
            Text(label)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.textSecondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }

    // MARK: Form

    private var form: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(String(localized: "HOW MANY WORDS")) {
                chips {
                    ForEach(StudyPlan.sizeChoices, id: \.self) { choice in
                        StudyChip(title: choice == 0 ? String(localized: "All waiting") : "\(choice)",
                                  isOn: size == choice) { size = choice }
                    }
                }
            } hint: {
                Text(durationHint)
            }
            Divider()
            row(String(localized: "FROM")) {
                chips {
                    StudyChip(title: String(localized: "All"), isOn: source == .all) { source = .all }
                    if let lastDocument, bookWordCount > 0 {
                        StudyChip(title: String(localized: "This book: \(lastDocument.displayTitle)"),
                                  isOn: source == .book(lastDocument.filename)) { source = .book(lastDocument.filename) }
                    }
                    if !store.allTags.isEmpty { deckMenu }
                    if strugglingCount > 0 {
                        StudyChip(title: String(localized: "You keep forgetting (\(strugglingCount))"),
                                  isOn: source == .struggling) { source = .struggling }
                    }
                }
            } hint: { EmptyView() }
            Divider()
            row(String(localized: "NEW WORDS")) {
                chips {
                    ForEach(StudyPlan.newLimitChoices, id: \.self) { choice in
                        StudyChip(title: choice == 0 ? String(localized: "None") : String(localized: "Up to \(choice)"),
                                  isOn: newLimit == choice) { newLimit = choice }
                    }
                }
            } hint: {
                Text("Words waiting for review come first; new ones are mixed in.")
            }
            Divider()
            row(String(localized: "HOW")) {
                chips {
                    ForEach(availableModes) { mode in
                        StudyChip(title: mode.localizedTitle, isOn: quizMode == mode) { quizMode = mode }
                    }
                }
            } hint: {
                if !quizMode.affectsSchedule {
                    Text("Practice: your review schedule stays as it is.")
                } else if quizMode == .mixed {
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text("New words: pick the right one. Learning: type the missing word. Settled: hear it and type it.")
                            .fixedSize(horizontal: false, vertical: true)
                        Toggle("Grade my typed answer automatically", isOn: $typedAutoGrade)
                            .toggleStyle(.checkbox)
                    }
                } else if quizMode.isObjectivelyGraded {
                    Toggle("Grade my typed answer automatically", isOn: $typedAutoGrade)
                        .toggleStyle(.checkbox)
                }
            }
            Divider()
            startRow
                .padding(DS.Spacing.md)
        }
        .dsCard(padding: nil)
    }

    private var deckMenu: some View {
        let selectedDeck: String? = if case .deck(let tag) = source { tag } else { nil }
        return Menu {
            ForEach(store.allTags, id: \.self) { tag in
                Button("\(tag) (\(store.tagCount(tag)))") { source = .deck(tag) }
            }
        } label: {
            Text(selectedDeck.map { String(localized: "Deck: \($0)") } ?? String(localized: "Deck"))
        }
        .menuStyle(.button)
        .controlSize(.small)
        .fixedSize()
        .tint(selectedDeck != nil ? DS.Color.accent : nil)
    }

    @ViewBuilder
    private var startRow: some View {
        HStack(spacing: DS.Spacing.md) {
            if !queue.isEmpty {
                Button(queue.count == 1 ? String(localized: "Start with 1 word") : String(localized: "Start with \(queue.count) words")) {
                    onStart(queue, false)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            } else if !practice.isEmpty {
                Button(String(localized: "Practice \(practice.count) words")) { onStart(practice, true) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                Text("Nothing is waiting here. Practice leaves your schedule as it is.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
            } else {
                Text("No words here yet.")
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Color.textSecondary)
            }
            Spacer(minLength: 0)
            Text("⌃⌘F full screen")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.textTertiary)
        }
        .controlSize(.large)
    }

    private var durationHint: String {
        // About 18 seconds a card, from the user's own review history pace.
        let minutes = max(1, Int((Double(queue.count) * 18 / 60).rounded()))
        return String(localized: "About \(minutes) min.")
    }

    // MARK: Pieces

    private func row<Content: View, Hint: View>(
        _ title: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder hint: () -> Hint
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(title).dsOverlineLabel()
            content()
            hint()
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Spacing.md)
    }

    /// One line of chips, or a column when they don't fit.
    private func chips<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let items = content()
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Spacing.xs) { items }
            VStack(alignment: .leading, spacing: DS.Spacing.xs) { items }
        }
    }
}

/// A choice in the setup form.
struct StudyChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DS.Typography.callout.weight(isOn ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 280)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.xs)
                .foregroundStyle(isOn ? DS.Color.accent : DS.Color.textPrimary)
                .background(isOn ? DS.Color.accentSubtle : DS.Color.surfaceInset, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
