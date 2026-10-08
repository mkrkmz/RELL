//
//  QuizView+Room.swift
//  Reader for Language Learner
//
//  The study room's side of `QuizView` (Roadmap v15 Sprint 2): its own
//  setup and summary, a large card with the book sentence, ratings that say
//  when the word comes back, and the keyboard — Space flips, 1–4 grade,
//  ← takes back the last grade, → puts the card at the end, S reads the
//  word, Esc ends the session.
//

import SwiftUI

extension QuizView {
    enum Style { case sidebar, room }

    /// How wide the room's card gets, however large the window.
    static let roomCardWidth: CGFloat = 680

    // MARK: Screens

    @ViewBuilder
    var roomContent: some View {
        if session.isFinished {
            StudySummaryView(
                session: session,
                store: store,
                mode: quizMode,
                onStudyAgain: { beginRoom(with: $0, practice: false) },
                onMore: { withAnimation(DS.Animation.standard) { session.reset() } },
                onClose: { onClose?() }
            )
        } else if !session.isActive {
            StudySetupView(
                store: store,
                lastDocument: recentDocuments?.documents.max { $0.lastOpenedAt < $1.lastOpenedAt },
                availableModes: availableModes,
                quizMode: Binding(get: { quizMode }, set: { quizModeRaw = $0.rawValue }),
                typedAutoGrade: $typedAutoGrade,
                onStart: { beginRoom(with: $0, practice: $1) }
            )
        } else if let word = session.currentWord {
            roomCard(for: word)
        }
    }

    func beginRoom(with words: [SavedWord], practice: Bool) {
        session.optionsBuilder = { buildOptions(for: $0) }
        session.modeResolver = { stageMode(for: $0) }
        session.introducesNewWords = !quizMode.isRoundBased
        session.cram = practice
        let run = quizMode.isRoundBased ? words.filter { $0.usableDefinition != nil } : words
        session.begin(with: run, mode: quizMode, shuffle: false)
        roomFocused = true
    }

    /// Esc: ends a session (to its summary); on the setup or summary screen
    /// it closes the window. The sidebar keeps its old meaning — close a
    /// modal host.
    func handleEscape() {
        if style == .room, session.isActive, !session.isFinished {
            session.finish()
        } else {
            onClose?()
        }
    }

    // MARK: Card

    func roomCard(for word: SavedWord) -> some View {
        VStack(spacing: DS.Spacing.lg) {
            roomProgress
            Spacer(minLength: 0)
            Group {
                if quizMode.isRoundBased {
                    matchingRound
                } else if session.isIntroducing {
                    introductionCard(for: word)
                } else {
                    switch cardMode {
                    case .flashcard:      flashcardBody(word)
                    case .multipleChoice: multipleChoiceBody(word)
                    case .typed:          typedBody(word)
                    case .listening:      listeningBody(word)
                    case .matching, .mixed: EmptyView()
                    }
                }
            }
            .frame(maxWidth: quizMode.isRoundBased ? .infinity : Self.roomCardWidth)
            Spacer(minLength: 0)
            if session.isFlipped && !quizMode.isRoundBased && !session.isIntroducing {
                Group {
                    if showsRatingRow { roomRatingRow(for: word) } else { autoGradeContinueRow(for: word) }
                }
                .frame(maxWidth: Self.roomCardWidth)
            }
            roomKeyHints
        }
        .padding(.horizontal, DS.Spacing.xl)
        .padding(.vertical, DS.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable()
        .focused($roomFocused)
        .focusEffectDisabled()
        // The flashcard handles these itself when it has focus; this is for
        // when the room does (after a grade, a take-back or a skip).
        .onKeyPress(keys: [.space, .return]) { _ in
            if session.isIntroducing {
                finishIntroduction()
                return .handled
            }
            guard cardMode == .flashcard, !session.isFlipped else { return .ignored }
            flipCard()
            return .handled
        }
        .onKeyPress(.leftArrow) { undoLastGrade() ? .handled : .ignored }
        .onKeyPress(.rightArrow) {
            withAnimation(DS.Animation.springFast) { session.skipCurrent(mode: quizMode) }
            return .handled
        }
        .onKeyPress(characters: ["s", "S"]) { _ in
            speak(word)
            return .handled
        }
        .onAppear { roomFocused = true }
        .animation(DS.Animation.springFast, value: session.isFlipped)
    }

    func finishIntroduction() {
        withAnimation(DS.Animation.springFast) { session.finishIntroduction(mode: quizMode) }
    }

    /// A word you've never reviewed, shown before it's asked (v15 S3): what
    /// it means, how it sounds, where you met it.
    func introductionCard(for word: SavedWord) -> some View {
        VStack(spacing: DS.Spacing.md) {
            cardFace(
                content: VStack(spacing: DS.Spacing.sm) {
                    Text("NEW WORD").dsOverlineLabel()
                    roomBack(for: word)
                },
                isFront: true
            )
            Button {
                finishIntroduction()
            } label: {
                Text("Got It — Ask Me Later")
                    .font(DS.Typography.callout.weight(.semibold))
                    .frame(maxWidth: 280)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .help("It comes back as a question a few cards later (Space)")
        }
        .onAppear { speak(word) }
    }

    @discardableResult
    func undoLastGrade() -> Bool {
        var undone = false
        withAnimation(DS.Animation.springFast) { undone = session.undoLast(in: store, mode: quizMode) }
        return undone
    }

    private var roomProgress: some View {
        HStack(spacing: DS.Spacing.md) {
            ProgressView(value: Double(min(session.position, session.total)), total: Double(max(session.total, 1)))
                .tint(DS.Color.accent)
            if session.cram {
                Label("Practice", systemImage: "gamecontroller")
                    .foregroundStyle(DS.Color.warning)
            }
            Text("\(session.position) / \(session.total)")
                .monospacedDigit()
        }
        .font(DS.Typography.caption.weight(.semibold))
        .foregroundStyle(DS.Color.textSecondary)
        .frame(maxWidth: Self.roomCardWidth + 120)
    }

    private var roomKeyHints: some View {
        HStack(spacing: DS.Spacing.lg) {
            keyHint("Space", String(localized: "flip"))
            keyHint("←", String(localized: "take back"))
            keyHint("→", String(localized: "skip"))
            keyHint("S", String(localized: "listen"))
            keyHint("Esc", String(localized: "end"))
        }
        .font(DS.Typography.caption)
        .foregroundStyle(DS.Color.textTertiary)
        .accessibilityElement(children: .combine)
    }

    private func keyHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: DS.Spacing.xxs) {
            Text(key)
                .font(DS.Typography.mono)
                .padding(.horizontal, DS.Spacing.xs)
                .padding(.vertical, 1)
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.sm).strokeBorder(DS.Color.hairlineStrong))
            Text(label)
        }
    }

    // MARK: Faces

    func roomFront(for word: SavedWord) -> some View {
        VStack(spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.xs) {
                if let cefr = word.cefrLevel.flatMap(CEFRLevel.init) {
                    Text(cefr.rawValue)
                        .font(DS.Typography.caption2.weight(.bold))
                        .foregroundStyle(cefr.badgeColor)
                        .padding(.horizontal, DS.Spacing.xs)
                        .background(cefr.badgeColor.opacity(0.12), in: Capsule())
                }
                Text(word.hasBeenReviewed ? String(localized: "Review") : String(localized: "New word"))
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
            }
            Text(word.term)
                .font(DS.Typography.studyWord)
                .foregroundStyle(DS.Color.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
            SpeakButton(text: word.term, size: 18, language: voiceLanguage(for: word))
            if sentenceOnFront, !word.sentence.isEmpty {
                roomSentence(word)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Card front: \(word.term)")
        .accessibilityHint("Press space to flip")
    }

    func roomBack(for word: SavedWord) -> some View {
        let meaning = FillField.meaning.value(in: word)
        let definition = FillField.definition.value(in: word)
        return cardScroll(maxHeight: 380) {
            VStack(spacing: DS.Spacing.md) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
                    Text(word.term)
                        .font(DS.Typography.wordDisplayLarge)
                        .foregroundStyle(DS.Color.textPrimary)
                    if let ipa = FillField.pronunciation.value(in: word) {
                        Text(ipa)
                            .font(DS.Typography.mono)
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                    SpeakButton(text: word.term, size: 14, language: voiceLanguage(for: word))
                }
                Divider()
                if meaning == nil && definition == nil {
                    // Nothing on the card: the sidebar's sections, with the
                    // dictionary's answer and "Add to Card" (v15 S1).
                    backSections(for: word, maxHeight: 260)
                } else {
                    if let meaning {
                        Text(meaning)
                            .font(DS.Typography.studyMeaning)
                            .foregroundStyle(DS.Color.textPrimary)
                    }
                    if let definition {
                        Text(definition)
                            .font(DS.Typography.body)
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                }
                if let hook = FillField.mnemonic.value(in: word) {
                    VStack(spacing: DS.Spacing.xxs) {
                        Text("MEMORY HOOK").dsOverlineLabel()
                        Text(hook)
                            .font(DS.Typography.callout)
                            .foregroundStyle(DS.Color.textPrimary)
                    }
                    .padding(DS.Spacing.sm)
                    .frame(maxWidth: .infinity)
                    .background(DS.Color.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: DS.Radius.md))
                }
                if !word.sentence.isEmpty {
                    roomSentence(word)
                }
                roomMoreModules(word)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        }
    }

    private func roomSentence(_ word: SavedWord) -> some View {
        VStack(spacing: DS.Spacing.xxs) {
            Text(WordPageModel.emphasized(word.sentence, term: word.term, language: voiceLanguage(for: word)))
                .font(DS.Typography.studyContext)
                .foregroundStyle(DS.Color.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(4)
            if let source = word.pdfFilename {
                Text(source.replacingOccurrences(of: "_", with: " ")
                     + (word.pageNumber.map { " · " + String(localized: "p. \($0)") } ?? ""))
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    /// The other saved outputs (examples, collocations…) behind one button.
    @ViewBuilder
    private func roomMoreModules(_ word: SavedWord) -> some View {
        let cardModules: Set<ModuleType> = [.meaningTR, .definitionEN, .pronunciationEN, .mnemonicEN]
        let others = savedModules(for: word).filter { !cardModules.contains($0) }
        if !others.isEmpty {
            if session.showAllBackSections {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    ForEach(others) { moduleSection($0, word: word) }
                }
                .multilineTextAlignment(.leading)
            } else {
                Button(others.count == 1 ? String(localized: "1 more saved") : String(localized: "\(others.count) more saved")) {
                    withAnimation(DS.Animation.standard) { session.showAllBackSections = true }
                }
                .buttonStyle(.link)
                .font(DS.Typography.caption)
            }
        }
    }

    // MARK: Ratings

    func roomRatingRow(for word: SavedWord) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            roomRating(.again, title: String(localized: "Again"), key: "1", tint: DS.Color.danger, word: word)
            roomRating(.hard, title: String(localized: "Hard"), key: "2", tint: DS.Color.warning, word: word)
            roomRating(.good, title: String(localized: "Good"), key: "3", tint: DS.Color.accent, word: word)
            roomRating(.easy, title: String(localized: "Easy"), key: "4", tint: DS.Color.success, word: word)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func roomRating(_ rating: ReviewRating, title: String, key: Character, tint: Color, word: SavedWord) -> some View {
        // When the word comes back after this grade — not in practice,
        // which leaves the schedule alone (approved decision 4).
        let next = session.cram ? nil : store.nextReviewDate(for: word, after: rating)
        return Button {
            recordRating(rating, word: word)
        } label: {
            VStack(spacing: 1) {
                Text(String(key))
                    .font(DS.Typography.mono)
                    .opacity(0.7)
                Text(title)
                    .font(DS.Typography.callout.weight(.semibold))
                if let next {
                    Text(StudyPlan.intervalLabel(from: Date(), to: next))
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                        .monospacedDigit()
                }
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.sm)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: DS.Radius.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(key), modifiers: [])
        .accessibilityLabel(next.map { "\(title), \(StudyPlan.intervalLabel(from: Date(), to: $0))" } ?? title)
    }
}
