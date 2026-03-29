//
//  InspectorView+ResultPanel.swift
//  Reader for Language Learner
//
//  Result panel: active module output + loading / error / empty states.
//

import SwiftUI

extension InspectorView {

    // MARK: - Result Panel

    var resultPanel: some View {
        Group {
            if let activeModule {
                activeResultView(for: activeModule)
                    .id(activeModule)
                    .transition(.opacity)
            } else {
                noModuleHint
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(DS.Animation.standard, value: activeModule)
    }

    // MARK: - No-Module Hint

    var noModuleHint: some View {
        VStack(spacing: DS.Spacing.md) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(DS.Color.textTertiary)
                .symbolEffect(.pulse.wholeSymbol, options: .repeating)
            Text("Choose a module above")
                .font(DS.Typography.subhead)
                .foregroundStyle(DS.Color.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Active Result

    @ViewBuilder
    func activeResultView(for module: ModuleType) -> some View {
        let output          = viewModel.outputs[module] ?? ""
        let sanitizedOutput = MarkdownUtils.sanitizeLLMOutput(output)
        let isLoading       = viewModel.loading[module] == true
        let elapsed         = moduleElapsed[module]

        VStack(alignment: .leading, spacing: 0) {

            // ── Result header ─────────────────────────────────────────────
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: module.iconName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(module.accentColor)

                Text(module.title(nativeLanguage: nativeLanguage))
                    .font(DS.Typography.label)
                    .foregroundStyle(DS.Color.textPrimary)

                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(DS.Color.accent)
                        .transition(.opacity)
                } else if let elapsed {
                    Text(String(format: "%.1fs", elapsed))
                        .font(DS.Typography.mono)
                        .foregroundStyle(DS.Color.textTertiary)
                        .transition(.opacity)
                }

                Spacer()

                HStack(spacing: DS.Spacing.xxs) {
                    Button {
                        Task { await runModule(module, forceRefresh: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh (⌘R)")
                    .keyboardShortcut("r", modifiers: [.command])
                    .disabled(isLoading || !isModuleEnabled(module))

                    Button { copyToClipboard(sanitizedOutput, showFeedback: true) } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .help("Copy result (⇧⌘C)")
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(sanitizedOutput.isEmpty)

                    if isLoading {
                        Button {
                            viewModel.cancel(module: module)
                            moduleElapsed[module] = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(DS.Color.danger.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .help("Cancel")
                    } else {
                        Button { activeModule = nil } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(DS.Color.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Close (Esc)")
                    }
                }
                .controlSize(.small)
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .background(DS.Color.accentSubtle)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))

            // ── Result body ───────────────────────────────────────────────
            resultBody(
                output: sanitizedOutput,
                error: viewModel.errors[module],
                isLoading: isLoading,
                module: module
            )
            .padding(.top, DS.Spacing.sm)
        }
    }

    // MARK: - Result Body

    @ViewBuilder
    func resultBody(
        output: String,
        error: String?,
        isLoading: Bool,
        module: ModuleType
    ) -> some View {
        if let error {
            errorView(error: error, module: module)
        } else if !output.isEmpty {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading) {
                        Color.clear.frame(height: 1).id("top")
                        ResultRenderer(content: output, module: module)
                            .padding(DS.Spacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .onChange(of: activeModule) { _, _ in
                    withAnimation { proxy.scrollTo("top", anchor: .top) }
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DS.Color.surfaceInset)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
            .lineSpacing(4)
        } else if isLoading {
            loadingView
        } else {
            emptyOutputView(module: module)
        }
    }

    // MARK: - Loading View

    var loadingView: some View {
        VStack(spacing: DS.Spacing.md) {
            Spacer()
            HStack(spacing: DS.Spacing.sm) {
                ProgressView().controlSize(.small)
                Text("Analyzing…")
                    .font(DS.Typography.subhead)
                    .foregroundStyle(DS.Color.textSecondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Color.surfaceInset)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
    }

    // MARK: - Empty Output View

    @ViewBuilder
    func emptyOutputView(module: ModuleType) -> some View {
        VStack(spacing: DS.Spacing.sm) {
            Spacer()
            Image(systemName: module.iconName)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(DS.Color.textTertiary)
            Text("Tap to run")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Color.surfaceInset)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
    }

    // MARK: - Error View

    @ViewBuilder
    func errorView(error: String, module: ModuleType) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(DS.Color.warning)
                Text(error)
                    .font(DS.Typography.subhead)
                    .foregroundStyle(DS.Color.danger)
                Spacer()
                Button("Retry") {
                    Task { await runModule(module, forceRefresh: true) }
                }
                .controlSize(.small)
            }
            .padding(DS.Spacing.md)
            .background(DS.Color.danger.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
            .textSelection(.enabled)
        }
    }
}
