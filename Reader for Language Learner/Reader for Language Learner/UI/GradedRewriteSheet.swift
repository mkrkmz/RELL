//
//  GradedRewriteSheet.swift
//  Reader for Language Learner
//
//  "Simplify to your level" (Roadmap v13 Sprint 3): the selected passage
//  next to the same passage rewritten at the reader's CEFR level.
//

import SwiftUI

struct GradedRewriteSheet: View {
    let source: String

    @Environment(\.dismiss) private var dismiss
    @AppStorage(StorageKey.learnerLevel) private var levelRaw = CEFRLevel.defaultLearnerLevel.rawValue

    @State private var rewritten: String?
    @State private var failure: String?
    @State private var isLoading = false

    private var level: CEFRLevel { CEFRLevel(rawValue: levelRaw) ?? .defaultLearnerLevel }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack {
                Text("Simplified to Your Level")
                    .font(DS.Typography.headline)
                Spacer()
                Picker("Level", selection: $levelRaw) {
                    ForEach(CEFRLevel.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)
                .help(Text("Your level — changing it here changes it everywhere"))
            }

            HStack(alignment: .top, spacing: DS.Spacing.md) {
                column(title: Text("Original"), text: source, isRewrite: false)
                column(title: Text("At \(level.rawValue)"), text: rewritten ?? "", isRewrite: true)
            }

            HStack {
                Text("Rewritten by your AI — meant to get you through the passage, not to replace it.")
                    .font(DS.Typography.caption2)
                    .foregroundStyle(DS.Color.textTertiary)
                Spacer()
                if let rewritten {
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(rewritten, forType: .string)
                    }
                }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DS.Spacing.lg)
        .frame(width: 760, height: 480)
        .task(id: levelRaw) { await rewrite() }
    }

    private func column(title: Text, text: String, isRewrite: Bool) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.xs) {
                title.dsOverlineLabel().textCase(.uppercase)
                if isRewrite, rewritten != nil {
                    SpeakButton(text: text, size: 11)
                }
            }
            ScrollView {
                Group {
                    if isRewrite && isLoading {
                        HStack(spacing: DS.Spacing.sm) {
                            ProgressView().controlSize(.small)
                            Text("Rewriting…")
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Color.textSecondary)
                        }
                    } else if isRewrite, let failure {
                        Text(failure)
                            .font(DS.Typography.callout)
                            .foregroundStyle(DS.Color.danger)
                    } else {
                        Text(text)
                            .font(DS.Typography.body)
                            .foregroundStyle(DS.Color.textPrimary)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(DS.Spacing.md)
            }
            .background(isRewrite ? DS.Color.accent.opacity(0.06) : DS.Color.surfaceInset)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
        }
        .frame(maxWidth: .infinity)
    }

    private func rewrite() async {
        isLoading = true
        failure = nil
        defer { isLoading = false }
        do {
            let raw = try await AppleOnDevice.chatWithFallback(
                system: GradedRewrite.systemPrompt(language: Language.storedTarget, level: level),
                user: GradedRewrite.userPrompt(passage: GradedRewrite.input(source)),
                temperature: 0.3,
                maxTokens: GradedRewrite.maxTokens
            )
            guard !Task.isCancelled else { return }
            if let cleaned = GradedRewrite.clean(raw) {
                rewritten = cleaned
            } else {
                failure = String(localized: "The AI returned nothing to show. Try again.")
            }
        } catch {
            guard !Task.isCancelled else { return }
            failure = error.localizedDescription
        }
    }
}
