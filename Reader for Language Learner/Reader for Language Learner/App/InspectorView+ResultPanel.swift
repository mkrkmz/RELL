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
        let isLoading       = viewModel.loading[module] == true
        let elapsed         = moduleElapsed[module]
        let isTruncated     = viewModel.wasTruncated[module] == true
        let renderedOutput  = isLoading ? output : MarkdownUtils.sanitizeLLMOutput(output)
        let outputLineCount = isLoading ? nil : (renderedOutput.isEmpty ? 0 : renderedOutput.components(separatedBy: .newlines).count)
        let sectionTitle    = isLoading ? "Live Output" : "Result"

        VStack(alignment: .leading, spacing: 0) {

            // ── Result header ─────────────────────────────────────────────
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack(alignment: .top, spacing: DS.Spacing.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: DS.Radius.sm)
                            .fill(module.accentColor.opacity(0.12))
                            .frame(width: 32, height: 32)
                        Image(systemName: module.iconName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(module.accentColor)
                    }

                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text(sectionTitle)
                            .dsOverlineLabel()

                        Text(module.title(nativeLanguage: nativeLanguage))
                            .font(DS.Typography.headline)
                            .foregroundStyle(DS.Color.textPrimary)
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

                        Button { copyToClipboard(renderedOutput, showFeedback: true) } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .help("Copy result (⇧⌘C)")
                        .keyboardShortcut("c", modifiers: [.command, .shift])
                        .disabled(renderedOutput.isEmpty)

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

                HStack(spacing: DS.Spacing.xs) {
                    resultMetaPill(
                        title: isLoading ? "Status" : "Output",
                        value: isLoading ? "Generating" : "\((outputLineCount ?? 0)) lines",
                        tint: isLoading ? DS.Color.accent : module.accentColor
                    )

                    if isLoading {
                        liveStatusBadge
                    }

                    if let elapsed, !isLoading {
                        resultMetaPill(
                            title: "Time",
                            value: String(format: "%.1fs", elapsed),
                            tint: DS.Color.textSecondary
                        )
                    }

                    if !isLoading && !renderedOutput.isEmpty {
                        resultMetaPill(
                            title: "Chars",
                            value: "\(renderedOutput.count)",
                            tint: DS.Color.textSecondary
                        )
                    }

                    if isTruncated && !isLoading {
                        truncationWarningBadge
                    }

                    Spacer(minLength: 0)
                }

                if hasSourceContext {
                    sourceContextPanel
                }
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .fill(DS.Color.surfaceElevated)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .strokeBorder(DS.Color.separator.opacity(0.35), lineWidth: 0.8)
            )
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .fill(module.accentColor.opacity(0.12))
                    .frame(height: 4)
                    .padding(.horizontal, 1)
                    .padding(.top, 1)
            }

            // ── Result body ───────────────────────────────────────────────
            resultBody(
                output: renderedOutput,
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
                    VStack(alignment: .leading, spacing: DS.Spacing.md) {
                        Color.clear.frame(height: 1).id("top")
                        if !isLoading {
                            HStack {
                                Text("Generated Content")
                                    .dsOverlineLabel()
                                Spacer()
                            }
                            .padding(.horizontal, DS.Spacing.md)
                            .padding(.top, DS.Spacing.md)
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
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .fill(DS.Color.surfaceInset)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .strokeBorder(DS.Color.separator.opacity(0.28), lineWidth: 0.8)
            )
            .lineSpacing(4)
        } else if isLoading {
            loadingView
        } else {
            emptyOutputView(module: module)
        }
    }

    func resultMetaPill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased())
                .font(DS.Typography.caption2.weight(.bold))
            Text(value)
                .font(DS.Typography.caption.weight(.medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xs)
        .background(DS.Color.surface.opacity(0.75))
        .clipShape(Capsule())
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
        .background(DS.Color.surface.opacity(0.72))
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
        HStack(spacing: DS.Spacing.xs) {
            Circle()
                .fill(DS.Color.accent)
                .frame(width: 7, height: 7)
                .symbolEffect(.pulse)
            Text("Streaming")
                .font(DS.Typography.caption.weight(.semibold))
        }
        .foregroundStyle(DS.Color.accent)
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xs)
        .background(DS.Color.accentSubtle)
        .clipShape(Capsule())
        .accessibilityLabel("Streaming output in progress")
    }

    var truncationWarningBadge: some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9, weight: .semibold))
            Text("May be incomplete")
                .font(DS.Typography.caption.weight(.semibold))
        }
        .foregroundStyle(DS.Color.warning)
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xs)
        .background(DS.Color.warning.opacity(0.12))
        .clipShape(Capsule())
        .help("The output may have been cut off due to the token limit. Try switching to 'Detailed' mode or increase max tokens in Settings.")
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
        .background(DS.Color.surfaceInset)
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
        .background(DS.Color.surfaceInset)
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
