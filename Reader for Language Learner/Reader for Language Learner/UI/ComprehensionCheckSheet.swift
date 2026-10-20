//
//  ComprehensionCheckSheet.swift
//  Reader for Language Learner
//
//  "What did you understand?" (Roadmap v19 Sprint 3, approved mockup):
//  three questions on what you've read — main idea, detail, why — answered
//  in the language you're learning (or, at A1–A2 if you choose, your own).
//  Each answer comes back with a verdict on its content, the fixes to its
//  language and the book's sentence it rests on, with "Show in Book".
//  Practice: nothing reaches the review schedule.
//

import SwiftUI

/// The end-of-chapter offer waiting at the page's foot.
struct ComprehensionOffer: Equatable {
    let key: String
    let chapterNumber: Int
}

struct ComprehensionCheckSheet: View {

    struct Request: Identifiable, Equatable {
        enum Source: Equatable {
            /// An EPUB chapter's text and how far into it the reader is.
            case chapter(text: String, readUpTo: Double)
            /// PDF pages, 0-based.
            case pages(url: URL, range: ClosedRange<Int>)
        }

        let id = UUID()
        /// "Chapter 3", "Pages 41–47".
        let title: String
        let historyKey: String
        let source: Source
    }

    let request: Request
    /// Opens the find bar on the quote.
    let onShowInBook: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(SavedWordsStore.self) private var store
    @AppStorage(StorageKey.comprehensionAnswersInNative) private var answersInNative = false

    private enum Phase: Equatable {
        case loading, answering, checking, results
    }

    @State private var phase: Phase = .loading
    @State private var passage = ""
    @State private var questions: [ComprehensionCheck.Question] = []
    @State private var answers: [Int: String] = [:]
    @State private var grades: [Int: ComprehensionCheck.Grade] = [:]
    @State private var failure: String?
    @State private var showsText = false
    @State private var task: Task<Void, Never>?

    private var target: Language { Language.storedTarget }
    private var native: Language { Language.storedNative }
    private var level: CEFRLevel { CEFRLevel.storedLearnerLevel }
    /// The own-language option is for beginners (approved decision 3).
    private var offersNativeAnswers: Bool { level == .a1 || level == .a2 || answersInNative }
    private var inNative: Bool { answersInNative && offersNativeAnswers }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    if phase == .loading {
                        HStack(spacing: DS.Spacing.sm) {
                            ProgressView().controlSize(.small)
                            Text("Writing three questions about \(request.title)…")
                                .foregroundStyle(DS.Color.textSecondary)
                        }
                        .padding(.vertical, DS.Spacing.lg)
                        .frame(maxWidth: .infinity)
                    }
                    ForEach(questions) { question in
                        questionBlock(question)
                    }
                    if showsText, !passage.isEmpty {
                        Text(passage)
                            .font(DS.Typography.callout)
                            .foregroundStyle(DS.Color.textSecondary)
                            .textSelection(.enabled)
                            .padding(DS.Spacing.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(DS.Color.surfaceInset, in: RoundedRectangle(cornerRadius: DS.Radius.sm))
                    }
                }
            }
            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            footer
        }
        .padding(DS.Spacing.lg)
        .frame(width: 640, height: 600)
        .onAppear(perform: start)
        .onDisappear { task?.cancel() }
    }

    // MARK: Parts

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text("\(request.title) · What did you understand?")
                    .font(DS.Typography.headline)
                Text(inNative ? String(localized: "Answer in \(native.nativeName) — only the content is checked.")
                              : String(localized: "Answer in \(target.nativeName); a short answer is enough."))
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textSecondary)
            }
            Spacer()
            if phase == .results {
                scoreText
            } else if offersNativeAnswers, phase == .answering {
                Toggle(String(localized: "Answer in \(native.nativeName)"), isOn: $answersInNative)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }
    }

    private func questionBlock(_ question: ComprehensionCheck.Question) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
                Text("\(question.id)")
                    .foregroundStyle(DS.Color.textTertiary)
                    .monospacedDigit()
                Text(question.text)
                    .font(DS.Typography.body.weight(.semibold))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: DS.Spacing.sm)
                if let grade = grades[question.id] {
                    verdictChip(grade.verdict)
                } else {
                    Text(question.kind.localizedTitle.uppercased())
                        .font(DS.Typography.caption2.weight(.bold))
                        .foregroundStyle(DS.Color.textTertiary)
                }
            }
            if phase == .results {
                result(for: question)
            } else {
                TextField(String(localized: "Your answer…"), text: answerBinding(question.id), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(DS.Typography.body)
                    .fontDesign(.serif)
                    .lineLimit(1...4)
                    .padding(DS.Spacing.sm)
                    .background(DS.Color.surfaceInset, in: RoundedRectangle(cornerRadius: DS.Radius.sm))
                    .disabled(phase == .checking)
                    .accessibilityLabel(Text("Answer to question \(question.id)"))
            }
        }
        .padding(DS.Spacing.sm)
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md).strokeBorder(DS.Color.hairline))
    }

    @ViewBuilder
    private func result(for question: ComprehensionCheck.Question) -> some View {
        let written = (answers[question.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let grade = grades[question.id] {
            if grade.verdict == .skipped {
                Text("No answer")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
            } else {
                Text(grade.corrected.map { WordDiff.attributed(WordDiff.diff(written, $0)) } ?? AttributedString(written))
                    .font(DS.Typography.body)
                    .fontDesign(.serif)
                    .textSelection(.enabled)
                if !grade.note.isEmpty {
                    Label {
                        Text(grade.note).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "lightbulb.fill").foregroundStyle(DS.Color.amber)
                    }
                    .font(DS.Typography.callout)
                }
                if let quote = grade.quote {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
                        Text("“\(quote)”")
                            .font(DS.Typography.callout)
                            .fontDesign(.serif)
                            .foregroundStyle(DS.Color.textSecondary)
                            .textSelection(.enabled)
                        Spacer(minLength: 0)
                        Button("Show in Book") {
                            onShowInBook(quote)
                            dismiss()
                        }
                        .buttonStyle(.link)
                        .font(DS.Typography.caption)
                    }
                    .padding(DS.Spacing.xs)
                    .background(DS.Color.surfaceInset, in: RoundedRectangle(cornerRadius: DS.Radius.sm))
                }
                let added = grade.corrected.map { WordDiff.addedWords(WordDiff.diff(written, $0)) } ?? []
                let unsaved = added.filter { store.lemmaMatchedWord(for: $0) == nil }
                if !unsaved.isEmpty {
                    HStack(spacing: DS.Spacing.xs) {
                        Text("Words from the correction:")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Color.textTertiary)
                        ForEach(unsaved, id: \.self) { term in
                            Button { save(term, from: grade.corrected ?? "") } label: {
                                Label(term, systemImage: "star")
                            }
                            .buttonStyle(.borderless)
                            .font(DS.Typography.caption)
                            .help("Save word")
                        }
                    }
                }
            }
        } else {
            Text(written)
                .font(DS.Typography.body)
                .fontDesign(.serif)
        }
    }

    /// The verdict in words and a mark, not colour alone.
    private func verdictChip(_ verdict: ComprehensionCheck.Verdict) -> some View {
        let (title, symbol, tint): (String, String, Color) = switch verdict {
        case .understood: (String(localized: "Understood"), "checkmark", DS.Color.success)
        case .partly:     (String(localized: "Partly"), "circle.lefthalf.filled", DS.Color.warning)
        case .missed:     (String(localized: "Missed"), "xmark", DS.Color.danger)
        case .skipped:    (String(localized: "Skipped"), "minus", DS.Color.textTertiary)
        }
        return Label(title, systemImage: symbol)
            .font(DS.Typography.caption.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.hairline)
            .background(tint.opacity(0.14), in: Capsule())
            .fixedSize()
    }

    private var scoreText: some View {
        let score = ComprehensionCheck.score(grades.filter { $0.value.verdict != .skipped })
        return HStack(spacing: DS.Spacing.xs) {
            Text("\(score.understood) of \(score.total) understood")
                .font(DS.Typography.caption.weight(.semibold))
                .foregroundStyle(DS.Color.textSecondary)
        }
    }

    private var footer: some View {
        HStack(spacing: DS.Spacing.sm) {
            if phase == .checking {
                ProgressView().controlSize(.small)
                Text("Checking…")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textSecondary)
            } else if phase != .loading {
                Toggle(String(localized: "Show the text"), isOn: $showsText)
                    .toggleStyle(.checkbox)
                    .help("Answering from memory works best")
            }
            Spacer()
            if phase == .results {
                Button("Try Again") { tryAgain() }
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if !questions.isEmpty {
                    Button("Check Answers") { check() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(!hasAnAnswer || phase == .checking)
                        .help("⌘↩")
                } else if failure != nil {
                    Button("Try Again") { start() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .controlSize(.large)
    }

    private var hasAnAnswer: Bool {
        answers.values.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func answerBinding(_ id: Int) -> Binding<String> {
        Binding(get: { answers[id] ?? "" }, set: { answers[id] = $0 })
    }

    // MARK: Actions

    private func start() {
        failure = nil
        phase = .loading
        questions = []
        let source = request.source
        let target = target, level = level
        task = Task {
            let text = await Task.detached(priority: .userInitiated) { () -> String in
                switch source {
                case .chapter(let text, let fraction): return ComprehensionCheck.chapterPassage(text, readUpTo: fraction)
                case .pages(let url, let range):      return ComprehensionCheck.pdfPassage(url: url, pages: range)
                }
            }.value
            guard !Task.isCancelled else { return }
            guard !text.isEmpty else {
                failure = String(localized: "There's no text here to ask about.")
                phase = .answering
                return
            }
            passage = text
            do {
                let raw = try await AppleOnDevice.chatWithFallback(
                    origin: .comprehension,
                    system: ComprehensionCheck.questionsSystemPrompt(target: target, level: level),
                    user: ComprehensionCheck.questionsUserPrompt(passage: text),
                    temperature: 0.4,
                    maxTokens: ComprehensionCheck.questionTokens
                )
                guard !Task.isCancelled else { return }
                questions = ComprehensionCheck.parseQuestions(raw)
                if questions.isEmpty {
                    failure = String(localized: "The AI's answer couldn't be read. Try again.")
                }
            } catch {
                guard !Task.isCancelled else { return }
                failure = error.localizedDescription
            }
            phase = .answering
        }
    }

    private func check() {
        failure = nil
        phase = .checking
        let given = Dictionary(uniqueKeysWithValues: questions.map { ($0.id, answers[$0.id] ?? "") })
        let passage = passage, questions = questions
        let system = ComprehensionCheck.gradeSystemPrompt(target: target, native: native, level: level, answersInNative: inNative)
        task = Task {
            do {
                let raw = try await AppleOnDevice.chatWithFallback(
                    origin: .comprehension,
                    system: system,
                    user: ComprehensionCheck.gradeUserPrompt(passage: passage, questions: questions, answers: given),
                    temperature: 0.2,
                    maxTokens: ComprehensionCheck.gradeTokens
                )
                guard !Task.isCancelled else { return }
                let parsed = ComprehensionCheck.parseGrades(raw, answers: given, passage: passage)
                guard parsed.values.contains(where: { $0.verdict != .skipped }) else {
                    failure = String(localized: "The AI's answer couldn't be read. Try again.")
                    phase = .answering
                    return
                }
                grades = parsed
                let score = ComprehensionCheck.score(parsed.filter { $0.value.verdict != .skipped })
                ComprehensionHistory.record(score.understood, of: score.total, for: request.historyKey)
                phase = .results
                Announcement.post(String(localized: "\(score.understood) of \(score.total) understood"))
            } catch {
                guard !Task.isCancelled else { return }
                failure = error.localizedDescription
                phase = .answering
            }
        }
    }

    private func tryAgain() {
        grades = [:]
        phase = .answering
    }

    private func save(_ term: String, from corrected: String) {
        guard store.lemmaMatchedWord(for: term) == nil else { return }
        let entry = EncounterScanner.Entry(id: UUID(), term: term)
        let sentence = EncounterScanner.scan(text: corrected, vocabulary: [entry], language: target).first?.sentence ?? ""
        store.add(SavedWord(term: term, sentence: sentence, language: target.rawValue))
    }
}
