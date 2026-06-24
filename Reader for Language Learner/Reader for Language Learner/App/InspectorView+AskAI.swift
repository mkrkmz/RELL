//
//  InspectorView+AskAI.swift
//  Reader for Language Learner
//
//  "Ask a follow-up" thread under the result panel. Reuses the streaming
//  provider, the local-request gate, and cancellation just like runModule.
//

import SwiftUI

extension InspectorView {

    // MARK: - Section

    @ViewBuilder
    var askAISection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            if !viewModel.followUps.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        ForEach(viewModel.followUps) { exchange in
                            followUpRow(exchange)
                        }
                    }
                    .padding(.bottom, DS.Spacing.xxs)
                }
                .frame(maxHeight: 188)
            }

            inputRow
        }
        .padding(.top, DS.Spacing.xs)
    }

    private func followUpRow(_ exchange: FollowUpExchange) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            HStack(alignment: .top, spacing: DS.Spacing.xs) {
                Image(systemName: "person.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(DS.Color.textTertiary)
                    .padding(.top, 2)
                Text(exchange.question)
                    .font(DS.Typography.caption.weight(.semibold))
                    .foregroundStyle(DS.Color.textPrimary)
                    .textSelection(.enabled)
            }

            HStack(alignment: .top, spacing: DS.Spacing.xs) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9))
                    .foregroundStyle(DS.Color.accent)
                    .padding(.top, 2)
                Group {
                    if let error = exchange.error {
                        Text(error)
                            .foregroundStyle(DS.Color.danger)
                    } else if exchange.answer.isEmpty && exchange.isLoading {
                        HStack(spacing: DS.Spacing.xs) {
                            ProgressView().controlSize(.small)
                            Text("Thinking…").foregroundStyle(DS.Color.textTertiary)
                        }
                    } else {
                        Text(exchange.answer)
                            .foregroundStyle(DS.Color.textSecondary)
                            .textSelection(.enabled)
                    }
                }
                .font(DS.Typography.caption)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Spacing.sm)
        .background(DS.Color.surfaceInset.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
    }

    private var inputRow: some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: "sparkles")
                .font(.system(size: 11))
                .foregroundStyle(DS.Color.accent)

            TextField("Ask a follow-up…", text: $followUpQuestion, axis: .vertical)
                .textFieldStyle(.plain)
                .font(DS.Typography.caption)
                .lineLimit(1...3)
                .onSubmit { submitFollowUp() }

            if viewModel.isAskingFollowUp {
                Button {
                    viewModel.followUpTask?.cancel()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .foregroundStyle(DS.Color.danger.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Stop")
            } else {
                Button(action: submitFollowUp) {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(canSubmitFollowUp ? DS.Color.accent : DS.Color.textTertiary)
                }
                .buttonStyle(.plain)
                .disabled(!canSubmitFollowUp)
                .help("Ask (↩)")
            }
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xs)
        .background(DS.Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.sm)
                .strokeBorder(DS.Color.separator.opacity(0.28), lineWidth: 0.6)
        )
    }

    private var canSubmitFollowUp: Bool {
        !followUpQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !viewModel.isAskingFollowUp
    }

    private func submitFollowUp() {
        guard canSubmitFollowUp else { return }
        let question = followUpQuestion
        followUpQuestion = ""
        askFollowUp(question)
    }

    // MARK: - Request

    func askFollowUp(_ rawQuestion: String) {
        let question = rawQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, hasSelection else { return }

        viewModel.followUpTask?.cancel()

        let exchangeID = UUID()
        viewModel.followUps.append(
            FollowUpExchange(id: exchangeID, question: question, answer: "", isLoading: true, error: nil)
        )

        let client = llmProvider
        let native = nativeLanguage

        var contextLines = ["Term/phrase: \(trimmedSelection)"]
        if let sentence = contextSentence?.trimmingCharacters(in: .whitespacesAndNewlines), !sentence.isEmpty {
            contextLines.append("Sentence: \(sentence)")
        }
        if let active = activeModule, let output = viewModel.outputs[active]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty {
            contextLines.append("Current explanation: \(String(output.prefix(800)))")
        }

        let system = """
        You are a concise language-learning tutor. Use the context to answer the learner's follow-up directly. Plain text, no preamble.
        If the question is written in \(native.nativeName), answer in \(native.nativeName); otherwise answer in English.
        \(contextLines.joined(separator: "\n"))
        """

        let isLocalProvider = llmProviderTypeRaw == LLMProviderType.lmStudio.rawValue
            || llmProviderTypeRaw == LLMProviderType.ollama.rawValue

        let task = Task {
            do {
                if isLocalProvider { await viewModel.localRequestGate.acquire() }
                defer { if isLocalProvider { viewModel.localRequestGate.release() } }
                try Task.checkCancellation()
                _ = try await client.stream(
                    system: system,
                    user: question,
                    temperature: 0.3,
                    maxTokens: 400,
                    topP: 0.9
                ) { token in
                    if let index = self.viewModel.followUps.firstIndex(where: { $0.id == exchangeID }) {
                        self.viewModel.followUps[index].answer += token
                    }
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        if let index = viewModel.followUps.firstIndex(where: { $0.id == exchangeID }) {
                            viewModel.followUps[index].error = LLMErrorMessage.userMessage(for: error)
                        }
                    }
                }
            }
            await MainActor.run {
                if let index = viewModel.followUps.firstIndex(where: { $0.id == exchangeID }) {
                    viewModel.followUps[index].isLoading = false
                }
                viewModel.followUpTask = nil
            }
        }
        viewModel.followUpTask = task
    }
}
