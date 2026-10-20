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
        if session.isFinished, quizMode == .write {
            WritingSummaryView(
                session: session,
                onMore: { withAnimation(DS.Animation.standard) { session.reset() } },
                onClose: { onClose?() }
            )
        } else if session.isFinished {
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
        session.introducesNewWords = !quizMode.isRoundBased && quizMode != .write
        // Writing is practice whatever the queue (v19 S3).
        session.cram = practice || !quizMode.affectsSchedule
        let asked = words.filter(quizMode.asks)
        let run = quizMode.isRoundBased ? asked.filter { $0.usableDefinition != nil } : asked
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
                } else if quizMode == .write {
                    cardFace(content: SentenceWritingCard(
                        word: word,
                        onChecked: { session.recordWriting($0) },
                        onSaved: { session.noteWritingSaved() },
                        onNext: { withAnimation(DS.Animation.springFast) { session.advanceWriting() } }
                    ), isFront: true)
                } else if session.isIntroducing {
                    introductionCard(for: word)
                } else {
                    switch cardMode {
                    case .flashcard where word.isSentence: sentenceBody(word)
                    case .flashcard:      flashcardBody(word)
                    case .multipleChoice: multipleChoiceBody(word)
                    case .typed:          typedBody(word)
                    case .listening:      listeningBody(word)
                    case .matching, .mixed, .write: EmptyView()
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
        // While an answer is being typed the keys are the text field's:
        // S is a letter and the arrows move the cursor (v15 S3 live pass).
        .onKeyPress(.leftArrow) {
            guard !isTypingAnswer else { return .ignored }
            return undoLastGrade() ? .handled : .ignored
        }
        .onKeyPress(.rightArrow) {
            guard !isTypingAnswer else { return .ignored }
            withAnimation(DS.Animation.springFast) { session.skipCurrent(mode: quizMode) }
            return .handled
        }
        .onKeyPress(characters: ["s", "S"]) { _ in
            guard !isTypingAnswer else { return .ignored }
            speak(word)
            return .handled
        }
        // A sentence card: T shows the text before the translation (v19 S2).
        .onKeyPress(characters: ["t", "T"]) { _ in
            guard word.isSentence, !session.isFlipped else { return .ignored }
            withAnimation(DS.Animation.standard) { sentenceTextShown = true }
            return .handled
        }
        .onAppear { roomFocused = true }
        .animation(DS.Animation.springFast, value: session.isFlipped)
    }

    /// The card on screen has a text field for the answer.
    var isTypingAnswer: Bool {
        if quizMode == .write { return true }
        return !session.isFlipped && !session.isIntroducing && (cardMode == .typed || cardMode == .listening)
    }

    func finishIntroduction() {
        withAnimation(DS.Animation.springFast) { session.finishIntroduction(mode: quizMode) }
    }

    /// A word you've never reviewed, shown before it's asked (v15 S3): what
    /// it means, how it sounds, where you met it.
    func introductionCard(for word: SavedWord) -> some View {
        VStack(spacing: DS.Spacing.md) {
            cardFace(
                content: roomBack(for: word),
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
            // v18 S5: the session's trail — every answer a slice in its colour.
            SessionTrail(ratings: session.answers.map(\.rating), total: session.total)
            if session.cram {
                Label("Practice", systemImage: "gamecontroller")
                    .foregroundStyle(DS.Color.warning)
            }
            Text("\(session.position) / \(session.total)")
                .monospacedDigit()
            let streak = store.reviewStreak().current
            if streak > 0 {
                Label("\(streak) days", systemImage: "flame.fill")
                    .foregroundStyle(DS.Color.warning)
                    .help("Days in a row you've studied")
            }
        }
        .font(DS.Typography.caption.weight(.semibold))
        .foregroundStyle(DS.Color.textSecondary)
        .frame(maxWidth: Self.roomCardWidth + 120)
    }

    private var roomKeyHints: some View {
        HStack(spacing: DS.Spacing.lg) {
            if quizMode == .write {
                keyHint("⌘↩", String(localized: "check"))
                keyHint("↩", String(localized: "next"))
            } else if isTypingAnswer {
                keyHint("↩", String(localized: "check"))
            } else if session.currentWord?.isSentence == true, !session.isFlipped {
                keyHint("S", String(localized: "listen"))
                keyHint("T", String(localized: "text"))
                keyHint("Space", String(localized: "translation"))
            } else {
                keyHint("Space", String(localized: "flip"))
                keyHint("←", String(localized: "take back"))
                keyHint("→", String(localized: "skip"))
                keyHint("S", String(localized: "listen"))
            }
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
                .padding(.vertical, DS.Spacing.hairline)
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.sm).strokeBorder(DS.Color.hairlineStrong))
            Text(label)
        }
    }

    // MARK: Faces

    func roomFront(for word: SavedWord) -> some View {
        VStack(spacing: DS.Spacing.md) {
            // The level and "new / review" are on the card's band (v18 S5).
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
                    // v18 S5: a warm box with a bulb — the hook should stand out.
                    HStack(alignment: .top, spacing: DS.Spacing.sm) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(DS.Color.amber)
                        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                            Text("MEMORY HOOK").dsOverlineLabel()
                            Text(hook)
                                .font(DS.Typography.callout)
                                .foregroundStyle(DS.Color.textPrimary)
                        }
                        .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(DS.Spacing.sm)
                    .frame(maxWidth: .infinity)
                    .background(
                        LinearGradient(colors: [DS.Color.amber.opacity(0.20), DS.Color.warning.opacity(0.08)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: DS.Radius.md)
                    )
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
            ForEach(Array([ReviewRating.again, .hard, .good, .easy].enumerated()), id: \.element) { index, rating in
                roomRating(rating, key: Character("\(index + 1)"), word: word)
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// v18 S5 (approved mockup): filled in the rating's colour with its mark
    /// — the colour makes it inviting, the mark and word say it.
    private func roomRating(_ rating: ReviewRating, key: Character, word: SavedWord) -> some View {
        // When the word comes back after this grade — not in practice,
        // which leaves the schedule alone (approved decision 4).
        let next = session.cram ? nil : store.nextReviewDate(for: word, after: rating)
        return Button {
            recordRating(rating, word: word)
        } label: {
            VStack(spacing: 1) {
                Text(String(key))
                    .font(DS.Typography.mono)
                    .opacity(0.8)
                Text("\(rating.mark) \(rating.localizedTitle)")
                    .font(DS.Typography.callout.weight(.bold))
                if let next {
                    Text(StudyPlan.intervalLabel(from: Date(), to: next))
                        .font(DS.Typography.caption)
                        .opacity(0.9)
                        .monospacedDigit()
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.sm)
            .background(
                LinearGradient(colors: [rating.tint.opacity(0.82), rating.tint],
                               startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: DS.Radius.md)
            )
            .shadow(color: rating.tint.opacity(0.25), radius: 4, y: 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(RoomRatingButtonStyle())
        .keyboardShortcut(KeyEquivalent(key), modifiers: [])
        .accessibilityLabel(next.map { "\(rating.localizedTitle), \(StudyPlan.intervalLabel(from: Date(), to: $0))" } ?? rating.localizedTitle)
    }

    // MARK: Liveliness (v18 S5)

    /// The band across the top of the card: what this card is, in colour
    /// and in words — the level, and a streak of remembered answers.
    func roomBand(for word: SavedWord) -> some View {
        let isNew = !word.hasBeenReviewed
        let writing = quizMode == .write
        let colors: [Color] = writing ? [DS.Color.warning, DS.Color.danger.opacity(0.75)]
            : word.isStruggling ? [DS.Color.danger, DS.Color.warning]
            : word.isSentence ? [DS.Color.violet, DS.Color.accent]
            : isNew ? [DS.Color.accent, DS.Color.violet] : [DS.Color.accent, DS.Color.accent.opacity(0.7)]
        let title = writing ? String(localized: "Write a Sentence")
            : word.isStruggling ? String(localized: "You keep forgetting · catch it this time")
            : word.isSentence ? String(localized: "Sentence")
            : isNew ? String(localized: "New word") : String(localized: "Review")
        let symbol = writing ? "pencil.line" : word.isStruggling ? "arrow.counterclockwise" : word.isSentence ? "quote.opening"
            : isNew ? "sparkle" : "circle.fill"
        return HStack(spacing: DS.Spacing.sm) {
            Label(title, systemImage: symbol)
                .imageScale(.small)
            Spacer(minLength: DS.Spacing.sm)
            if roomCombo >= 3 {
                Label("\(roomCombo) in a row", systemImage: "checkmark")
                    .imageScale(.small)
                    .padding(.horizontal, DS.Spacing.xs)
                    .background(.white.opacity(0.22), in: Capsule())
                    .help("Answers in a row you remembered")
            }
            if let cefr = word.cefrLevel.flatMap(CEFRLevel.init) {
                Text(cefr.rawValue)
                    .padding(.horizontal, DS.Spacing.xs)
                    .background(.white.opacity(0.22), in: Capsule())
            }
        }
        .font(DS.Typography.caption.weight(.bold))
        .foregroundStyle(.white)
        .lineLimit(1)
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.xs)
        .frame(maxWidth: .infinity)
        .background(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
        .accessibilityElement(children: .combine)
    }

    /// Answers in a row, from the latest back, that weren't "Again".
    var roomCombo: Int {
        SessionTrail.combo(session.answers.map(\.rating))
    }
}

/// Presses in a little and brightens on hover — the buttons feel alive.
private struct RoomRatingButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(hovering ? 0.05 : 0)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : DS.Animation.fast, value: configuration.isPressed)
    }
}
