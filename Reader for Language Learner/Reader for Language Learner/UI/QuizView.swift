//
//  QuizView.swift
//  Reader for Language Learner
//
//  Flashcard-style quiz over saved words.
//  Front: term. Back: definition (or first available LLM output).
//  "Know it" → mastery++, "Again" → stays in queue.
//

import SwiftUI

struct QuizView: View {
    var store: SavedWordsStore

    @State private var queue: [SavedWord] = []
    @State private var currentIndex = 0
    @State private var isFlipped = false
    @State private var sessionKnown = 0
    @State private var sessionAgain = 0
    @State private var isFinished = false
    @State private var flipRotation: Double = 0

    // Filter: only non-mastered words by default
    @State private var includeAll = false

    private var wordsToQuiz: [SavedWord] {
        includeAll
            ? store.words
            : store.words.filter { $0.masteryLevel != .mastered }
    }

    var body: some View {
        Group {
            if store.words.isEmpty {
                emptyState
            } else if wordsToQuiz.isEmpty {
                allMasteredState
            } else if isFinished {
                resultState
            } else if queue.isEmpty {
                startState
            } else {
                quizCard
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(DS.Animation.standard, value: isFinished)
    }

    // MARK: - Start Screen

    private var startState: some View {
        VStack(spacing: DS.Spacing.lg) {
            Spacer()

            Image(systemName: "brain.filled.head.profile")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(DS.Color.accent)

            VStack(spacing: DS.Spacing.xs) {
                Text("Vocabulary Quiz")
                    .font(DS.Typography.headline)
                    .foregroundStyle(DS.Color.textPrimary)
                Text("\(wordsToQuiz.count) words ready")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
            }

            Toggle("Include mastered words", isOn: $includeAll)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(DS.Typography.caption)
                .tint(DS.Color.accent)

            Button("Start Quiz") { beginQuiz() }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

            Spacer()
        }
        .padding(DS.Spacing.lg)
    }

    // MARK: - Quiz Card

    private var quizCard: some View {
        let word = queue[currentIndex]

        return VStack(spacing: DS.Spacing.lg) {
            // Progress
            ProgressView(value: Double(currentIndex), total: Double(queue.count))
                .tint(DS.Color.accent)
                .padding(.horizontal, DS.Spacing.md)

            Text("\(currentIndex + 1) / \(queue.count)")
                .font(DS.Typography.caption2)
                .foregroundStyle(DS.Color.textTertiary)

            Spacer()

            // Card
            ZStack {
                // Back face
                cardFace(content: backContent(for: word), isFront: false)
                    .rotation3DEffect(.degrees(isFlipped ? 0 : -90), axis: (x: 0, y: 1, z: 0))
                    .opacity(isFlipped ? 1 : 0)

                // Front face
                cardFace(content: frontContent(for: word), isFront: true)
                    .rotation3DEffect(.degrees(isFlipped ? 90 : 0), axis: (x: 0, y: 1, z: 0))
                    .opacity(isFlipped ? 0 : 1)
            }
            .onTapGesture { flipCard() }

            // Hint
            if !isFlipped {
                Text("Tap to reveal")
                    .font(DS.Typography.caption2)
                    .foregroundStyle(DS.Color.textTertiary)
            }

            Spacer()

            // Action buttons (only shown after flip)
            if isFlipped {
                HStack(spacing: DS.Spacing.lg) {
                    actionButton(
                        label: "Again",
                        icon: "arrow.counterclockwise",
                        color: DS.Color.danger
                    ) { handleAgain(word: word) }

                    actionButton(
                        label: "Know it",
                        icon: "checkmark.circle.fill",
                        color: DS.Color.success
                    ) { handleKnown(word: word) }
                }
                .padding(.horizontal, DS.Spacing.xl)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.vertical, DS.Spacing.md)
        .animation(DS.Animation.springFast, value: isFlipped)
    }

    // MARK: - Card Faces

    private func cardFace(content: some View, isFront: Bool) -> some View {
        content
            .padding(DS.Spacing.lg)
            .frame(maxWidth: .infinity, minHeight: 160)
            .background(DS.Color.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .strokeBorder(DS.Color.separator.opacity(0.4), lineWidth: 0.8)
            )
            .dsShadow(DS.Shadow.card)
            .padding(.horizontal, DS.Spacing.md)
    }

    private func frontContent(for word: SavedWord) -> some View {
        VStack(spacing: DS.Spacing.sm) {
            Text("TERM")
                .font(DS.Typography.caption2.weight(.bold))
                .foregroundStyle(DS.Color.textTertiary)
            Text(word.term)
                .font(.system(size: 28, weight: .semibold, design: .default))
                .foregroundStyle(DS.Color.textPrimary)
                .multilineTextAlignment(.center)
            masteryBadge(word.masteryLevel)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Flashcard front: \(word.term), mastery level \(word.masteryLevel.label)")
        .accessibilityHint("Tap to flip and see the definition")
    }

    private func backContent(for word: SavedWord) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("DEFINITION")
                .font(DS.Typography.caption2.weight(.bold))
                .foregroundStyle(DS.Color.textTertiary)
            Text(backText(for: word))
                .font(DS.Typography.body)
                .foregroundStyle(DS.Color.textPrimary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func backText(for word: SavedWord) -> String {
        // Priority: definition → native meaning → first available output
        let priority: [String] = [
            ModuleType.definitionEN.rawValue,
            ModuleType.meaningTR.rawValue,
        ]
        for key in priority {
            if let text = word.llmOutputs[key], !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        }
        return word.llmOutputs.values.first(where: { !$0.isEmpty })
            ?? (word.sentence.isEmpty ? "No definition saved." : word.sentence)
    }

    // MARK: - Action Button

    private func actionButton(
        label: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: DS.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                Text(label)
                    .font(DS.Typography.caption.weight(.semibold))
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.md)
            .background(color.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Result Screen

    private var resultState: some View {
        VStack(spacing: DS.Spacing.lg) {
            Spacer()

            Image(systemName: sessionAgain == 0 ? "star.fill" : "checkmark.circle.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(sessionAgain == 0 ? .yellow : DS.Color.success)

            VStack(spacing: DS.Spacing.xs) {
                Text("Session Complete!")
                    .font(DS.Typography.headline)
                    .foregroundStyle(DS.Color.textPrimary)
                HStack(spacing: DS.Spacing.lg) {
                    resultStat(value: "\(sessionKnown)", label: "Known", color: DS.Color.success)
                    resultStat(value: "\(sessionAgain)", label: "Again", color: DS.Color.danger)
                }
            }

            Button("Start Over") {
                isFinished = false
                beginQuiz()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            Spacer()
        }
        .padding(DS.Spacing.lg)
    }

    private func resultStat(value: String, label: String, color: Color) -> some View {
        VStack(spacing: DS.Spacing.xxs) {
            Text(value)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(DS.Typography.caption2)
                .foregroundStyle(DS.Color.textTertiary)
        }
    }

    // MARK: - Empty / All Mastered

    private var emptyState: some View {
        DSEmptyState(
            icon: "star",
            title: "No saved words",
            message: "Save vocabulary while reading to start a quiz."
        )
    }

    private var allMasteredState: some View {
        VStack(spacing: DS.Spacing.lg) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(DS.Color.success)
            VStack(spacing: DS.Spacing.xs) {
                Text("All words mastered!")
                    .font(DS.Typography.headline)
                    .foregroundStyle(DS.Color.textPrimary)
                Text("Enable \"Include mastered words\" to review them.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
                    .multilineTextAlignment(.center)
            }
            Toggle("Include mastered words", isOn: $includeAll)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(DS.Typography.caption)
                .tint(DS.Color.accent)
            Spacer()
        }
        .padding(DS.Spacing.lg)
    }

    // MARK: - Mastery Badge

    private func masteryBadge(_ level: MasteryLevel) -> some View {
        Label(level.label, systemImage: level.icon)
            .font(DS.Typography.caption2.weight(.semibold))
            .foregroundStyle(level.color)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.xxs + 1)
            .background(level.color.opacity(0.12))
            .clipShape(Capsule())
    }

    // MARK: - Logic

    private func beginQuiz() {
        queue = wordsToQuiz.shuffled()
        currentIndex = 0
        isFlipped = false
        sessionKnown = 0
        sessionAgain = 0
        isFinished = false
    }

    private func flipCard() {
        withAnimation(.easeInOut(duration: 0.25)) { isFlipped = true }
    }

    private func handleKnown(word: SavedWord) {
        sessionKnown += 1
        // Advance mastery (capped at .mastered)
        if word.masteryLevel != .mastered {
            store.setMastery(word.masteryLevel.next, for: word)
        }
        advance()
    }

    private func handleAgain(word: SavedWord) {
        sessionAgain += 1
        // Move to end of queue for another shot
        queue.append(word)
        advance()
    }

    private func advance() {
        isFlipped = false
        let next = currentIndex + 1
        if next >= queue.count {
            isFinished = true
        } else {
            withAnimation(DS.Animation.springFast) { currentIndex = next }
        }
    }
}
