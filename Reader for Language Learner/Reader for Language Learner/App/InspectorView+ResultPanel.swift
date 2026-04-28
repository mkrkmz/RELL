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
            Text("Results will stay here while you switch between modules.")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.textTertiary.opacity(0.78))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 220)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Color.surfaceInset.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .strokeBorder(DS.Color.separator.opacity(0.24), lineWidth: 0.6)
        )
    }

    // MARK: - Active Result

    @ViewBuilder
    func activeResultView(for module: ModuleType) -> some View {
        let output          = viewModel.outputs[module] ?? ""
        let isLoading       = viewModel.loading[module] == true
        let elapsed         = moduleElapsed[module]
        let isTruncated     = viewModel.wasTruncated[module] == true
        let renderedOutput  = isLoading ? output : MarkdownUtils.sanitizeLLMOutput(output)
        let sectionTitle    = isLoading ? "Live Output" : "Result"

        VStack(alignment: .leading, spacing: 0) {

            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: module.iconName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(module.accentColor)
                    .frame(width: 20, height: 20)
                    .background(module.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xs))

                VStack(alignment: .leading, spacing: 1) {
                    Text(sectionTitle)
                        .dsOverlineLabel()
                    Text(module.title(nativeLanguage: nativeLanguage))
                        .font(DS.Typography.subhead.weight(.semibold))
                        .foregroundStyle(DS.Color.textPrimary)
                        .lineLimit(1)
                }

                if isLoading {
                    liveStatusBadge
                }

                Spacer(minLength: 0)

                if let elapsed, !isLoading {
                    Text(String(format: "%.1fs", elapsed))
                        .font(DS.Typography.caption2.weight(.medium))
                        .foregroundStyle(DS.Color.textTertiary)
                }

                if isTruncated && !isLoading {
                    truncationWarningBadge
                }

                HStack(spacing: DS.Spacing.xxs) {
                    resultToolbarButton(systemImage: "arrow.clockwise") {
                        Task { await runModule(module, forceRefresh: true) }
                    }
                    .help("Refresh (⌘R)")
                    .keyboardShortcut("r", modifiers: [.command])
                    .disabled(isLoading || !isModuleEnabled(module))

                    resultToolbarButton(systemImage: "doc.on.doc") {
                        copyToClipboard(renderedOutput, showFeedback: true)
                    }
                    .help("Copy result (⇧⌘C)")
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(renderedOutput.isEmpty)

                    if isLoading {
                        resultToolbarButton(systemImage: "xmark.circle.fill") {
                            viewModel.cancel(module: module)
                            moduleElapsed[module] = nil
                        }
                        .foregroundStyle(DS.Color.danger.opacity(0.78))
                        .help("Cancel")
                    } else {
                        resultToolbarButton(systemImage: "xmark.circle.fill") {
                            activeModule = nil
                        }
                        .help("Close (Esc)")
                    }
                }
                .controlSize(.small)
            }
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.xs)
            .background(DS.Color.surfaceElevated)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(module.accentColor)
                    .frame(height: 2)
            }

            // ── Result body ───────────────────────────────────────────────
            resultBody(
                output: renderedOutput,
                error: viewModel.errors[module],
                isLoading: isLoading,
                module: module,
                showSourceContext: hasSourceContext
            )
        }
        .background(DS.Color.surface.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .strokeBorder(DS.Color.separator.opacity(0.24), lineWidth: 0.6)
        )
    }

    private func resultToolbarButton(
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 26, height: 26)
                .background(DS.Color.surfaceInset)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                        .strokeBorder(DS.Color.separator.opacity(0.18), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Result Body

    @ViewBuilder
    func resultBody(
        output: String,
        error: String?,
        isLoading: Bool,
        module: ModuleType,
        showSourceContext: Bool = false
    ) -> some View {
        if let error {
            errorView(error: error, module: module)
        } else if !output.isEmpty {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        Color.clear.frame(height: 1).id("top")

                        if showSourceContext {
                            sourceContextPanel
                                .padding(.horizontal, DS.Spacing.md)
                                .padding(.top, DS.Spacing.sm)
                        }

                        ResultRenderer(
                            content: output,
                            module: module,
                            prefersStreamingRenderer: isLoading,
                            showsContextBreakout: shouldShowContextBreakout(for: module)
                        )
                            .padding(.horizontal, DS.Spacing.md)
                            .padding(.bottom, DS.Spacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Color.clear.frame(height: 1).id("stream-bottom")
                    }
                }
                .onChange(of: activeModule) { _, _ in
                    withAnimation { proxy.scrollTo("top", anchor: .top) }
                }
                .onChange(of: output) { _, _ in
                    if isLoading {
                        proxy.scrollTo("stream-bottom", anchor: .bottom)
                    }
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DS.Color.surfaceInset.opacity(0.96))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            .lineSpacing(4)
        } else if isLoading {
            loadingView
        } else {
            emptyOutputView(module: module)
        }
    }

    var hasSourceContext: Bool {
        let hasSource = pdfFilename?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let hasSentence = contextSentence?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        return hasSource || hasSentence
    }

    var sourceContextPanel: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(alignment: .center, spacing: DS.Spacing.sm) {
                Label("Source Context", systemImage: "doc.text.magnifyingglass")
                    .font(DS.Typography.caption.weight(.semibold))
                    .foregroundStyle(DS.Color.textSecondary)

                Spacer(minLength: 0)

                if let sourceLabel {
                    Text(sourceLabel)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                        .lineLimit(1)
                }
            }

            if let sentence = trimmedContextSentence {
                Text("“\(sentence)”")
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Color.textPrimary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let sourceLabel {
                Text(sourceLabel)
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DS.Spacing.md)
        .background(DS.Color.surface.opacity(0.86))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .strokeBorder(DS.Color.separator.opacity(0.22), lineWidth: 0.8)
        )
    }

    var sourceLabel: String? {
        guard let pdfFilename, !pdfFilename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        if let pageNumber {
            return "\(pdfFilename) · p.\(pageNumber)"
        }

        return pdfFilename
    }

    var trimmedContextSentence: String? {
        guard let contextSentence else { return nil }
        let trimmed = contextSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func shouldShowContextBreakout(for module: ModuleType) -> Bool {
        guard explainMode == .word, trimmedContextSentence != nil else { return false }
        switch module {
        case .definitionEN, .meaningTR:
            return true
        default:
            return false
        }
    }

    var liveStatusBadge: some View {
        Circle()
            .fill(DS.Color.accent)
            .frame(width: 6, height: 6)
            .scaleEffect(1.0)
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: true)
            .accessibilityLabel("Streaming output in progress")
    }

    var truncationWarningBadge: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 10))
            .foregroundStyle(DS.Color.warning)
            .help("Output may be incomplete — try 'Detailed' mode or increase max tokens in Settings.")
            .accessibilityLabel("Warning: output may be incomplete due to token limit")
    }

    // MARK: - Loading View

    var loadingView: some View {
        VStack(spacing: DS.Spacing.md) {
            Spacer()

            VStack(spacing: DS.Spacing.sm) {
                ProgressView().controlSize(.small)
                Text("Analyzing…")
                    .font(DS.Typography.subhead)
                    .foregroundStyle(DS.Color.textSecondary)
                Text("The response will appear here as soon as the model starts producing text.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Color.surfaceInset.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    // MARK: - Empty Output View

    @ViewBuilder
    func emptyOutputView(module: ModuleType) -> some View {
        VStack(spacing: DS.Spacing.sm) {
            Spacer()
            Image(systemName: module.iconName)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(DS.Color.textTertiary)
            Text("Run this module to generate an explanation.")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Color.surfaceInset.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
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
