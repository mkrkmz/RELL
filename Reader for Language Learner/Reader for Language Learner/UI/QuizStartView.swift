//
//  QuizStartView.swift
//  Reader for Language Learner
//
//  What the Review Center offers before a run starts: the queue summary, the
//  mode, and the switches that shape the session. Split out of `QuizView`
//  (Roadmap v11 Sprint 1); the list view still owns the state and passes it
//  down as bindings.
//

import SwiftUI

struct QuizStartView: View {
    var store: SavedWordsStore
    @Bindable var session: QuizSession

    /// The queue as the parent computed it — this view narrows it with the
    /// switches below, but doesn't own the rules.
    let wordsToQuiz: [SavedWord]
    let dueWords: [SavedWord]
    let isUsingFallbackQueue: Bool
    /// Modes that can actually be run right now: listening needs a voice, the
    /// matching game needs enough pairs.
    let availableModes: [QuizMode]

    @Binding var quizMode: QuizMode
    @Binding var includeAll: Bool
    @Binding var selectedTag: String?
    @Binding var typedAutoGrade: Bool

    let onStart: () -> Void


    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: DS.Spacing.lg) {
                Image(systemName: "brain.filled.head.profile")
                    .font(DS.Typography.icon(38, weight: .light))
                    .foregroundStyle(DS.Color.accent)

                VStack(spacing: DS.Spacing.xs) {
                    Text("Review Center")
                        .font(DS.Typography.headline)
                        .foregroundStyle(DS.Color.textPrimary)
                    Text(startSummaryText)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DS.Spacing.sm) {
                    QuizStatTile(icon: "clock.badge.exclamationmark", value: "\(dueWords.count)", label: "Due now", color: dueWords.isEmpty ? DS.Color.success : DS.Color.warning)
                    QuizStatTile(icon: "sparkles", value: "\(store.newCount)", label: "New", color: DS.Color.accent)
                    QuizStatTile(icon: "brain", value: "\(store.learningCount)", label: "Learning", color: DS.Color.warning)
                    QuizStatTile(icon: "checkmark.seal", value: "\(store.masteredCount)", label: "Mastered", color: DS.Color.success)
                    QuizStatTile(icon: "checkmark.circle", value: "\(store.reviewedTodayCount)", label: "Reviewed today", color: DS.Color.success)
                }

                // A Menu rather than a segmented picker: four modes no longer
                // fit the sidebar's width.
                Menu {
                    ForEach(availableModes) { mode in
                        Button {
                            quizMode = mode
                        } label: {
                            Label(
                                mode.localizedTitle,
                                systemImage: mode == quizMode ? "checkmark" : mode.icon
                            )
                        }
                    }
                } label: {
                    Label(quizMode.localizedTitle, systemImage: quizMode.icon)
                        .font(DS.Typography.caption)
                }
                .menuStyle(.borderlessButton)
                .controlSize(.small)
                .fixedSize()
                .help("Reveal a flashcard, pick the word for a definition, type the missing word, type what you hear, or pair words with their meanings.")

                // Said before the run, not only after it: picking a mode that
                // doesn't count is a choice, not a surprise.
                if !quizMode.affectsSchedule {
                    Label("Practice mode — your review schedule stays as it is.", systemImage: "gamecontroller")
                        .font(DS.Typography.caption2)
                        .foregroundStyle(DS.Color.textTertiary)
                }

                if quizMode.isObjectivelyGraded {
                    Toggle("Grade my typed answer automatically", isOn: $typedAutoGrade)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .font(DS.Typography.caption)
                        .tint(DS.Color.accent)
                        .help("Right or wrong is decided by the check. Turn off to rate every card yourself.")
                }

                Toggle("Include all saved words", isOn: $includeAll)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(DS.Typography.caption)
                    .tint(DS.Color.accent)
                    .help("Review every saved word instead of the due-first queue.")

                Toggle("Cram — practice without changing the schedule", isOn: $session.cram)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(DS.Typography.caption)
                    .tint(DS.Color.warning)
                    .help("Drill cards without affecting spaced-repetition timing.")

                if !store.allTags.isEmpty {
                    Menu {
                        Button {
                            selectedTag = nil
                        } label: {
                            Label("All decks", systemImage: selectedTag == nil ? "checkmark" : "")
                        }
                        Divider()
                        ForEach(store.allTags, id: \.self) { tag in
                            Button {
                                selectedTag = tag
                            } label: {
                                Label(
                                    "\(tag) (\(store.tagCount(tag)))",
                                    systemImage: selectedTag?.lowercased() == tag.lowercased() ? "checkmark" : ""
                                )
                            }
                        }
                    } label: {
                        Label(selectedTag.map { "Deck: \($0)" } ?? "All decks", systemImage: "tag")
                            .font(DS.Typography.caption)
                    }
                    .menuStyle(.borderlessButton)
                    .controlSize(.small)
                    .fixedSize()
                    .help("Review only words in a deck (tag).")
                }

                Button {
                    onStart()
                } label: {
                    Label("Start Review", systemImage: "play.fill")
                        .font(DS.Typography.callout.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
                .help("Start the current review queue")
            }
            .padding(DS.Spacing.lg)
        }
    }

    private var startSummaryText: String {
        if includeAll {
            return "\(wordsToQuiz.count) saved words are ready for an all-in review."
        }
        if !dueWords.isEmpty {
            return "\(dueWords.count) words are due now. Start here to keep the review queue moving."
        }
        if isUsingFallbackQueue {
            return "No words are due right now, so Review Center will practice new and learning words."
        }
        return "Your review queue is clear."
    }
}
