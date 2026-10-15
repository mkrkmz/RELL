//
//  InspectorView+Custom.swift
//  Reader for Language Learner
//
//  The reader's own modules in the Inspector (Roadmap v18 Sprint 3,
//  approved mockup): opened from the card like the built-in ones, sent
//  through the same queue and request log, answered in the same panel with
//  the same footer — but kept apart from the built-in modules' cache,
//  parsers and per-module settings.
//

import SwiftUI

/// What Settings ▸ Prompts should open (from the Inspector).
enum CustomModuleEditorTarget: Equatable {
    case new
    case edit(UUID)
}

extension InspectorView {

    /// The own module whose answer is shown, if it still exists and runs on
    /// this card.
    var displayedCustom: CustomModule? {
        guard hasSelection, let activeCustom, let module = CustomModuleStore.shared.module(activeCustom),
              module.runs(on: cardKind) else { return nil }
        return module
    }

    func toggleCustom(_ id: UUID) {
        guard let module = CustomModuleStore.shared.module(id) else { return }
        activeCustom = id
        if (viewModel.customOutputs[id] ?? "").isEmpty, viewModel.customLoading[id] != true {
            runCustom(module, force: false)
        }
    }

    /// With auto-run on, a new selection opens on the own module you had
    /// open. True when one was open (so the built-in auto-run stays out).
    func runOpenCustomForNewSelection() -> Bool {
        guard let module = displayedCustom else { return false }
        runCustom(module, force: false)
        return true
    }

    func runCustom(_ module: CustomModule, force: Bool) {
        guard hasSelection else { return }
        let key = customCacheKey(module)
        if !force, viewModel.loadCustomFromCache(module.id, key: key) { return }

        let native = nativeLanguage
        let target = targetLanguage
        let values: [CustomPrompt.Placeholder: String] = [
            .selection: trimmedSelection,
            .sentence: contextSentence ?? "",
            .book: pdfFilename.map(BookIdentity.displayTitle) ?? "",
            .native: native.nativeName,
            .target: target.nativeName,
            .level: CEFRLevel.storedLearnerLevel.rawValue,
        ]
        let preamble = UserDefaults.standard.string(forKey: StorageKey.customSystemPreamble) ?? ""
        let useApple = module.engine == .apple && AppleOnDevice.currentRoute(for: nil) == .appleOnDevice
        let base: any LLMProvider = useApple ? AppleOnDevice.provider(for: nil)
                                             : ResilientLLMProvider(provider: LLMConfiguration().makeProvider(),
                                                                    circuitBreaker: circuitBreaker)
        let provider = LLMRequestLog.shared.recording(base, origin: .custom,
                                                      route: useApple ? .appleOnDevice : .configured)
        viewModel.startCustom(
            module.id,
            system: CustomPrompt.system(for: module, native: native, target: target, preamble: preamble),
            user: CustomPrompt.render(module.prompt, values: values),
            maxTokens: module.maxTokens,
            cacheKey: key,
            provider: provider
        )
    }

    private func customCacheKey(_ module: CustomModule) -> String {
        [trimmedSelection.lowercased(), contextSentence ?? "", CustomPrompt.cacheTag(module),
         module.engine == .apple ? AppleOnDevice.providerLabel : llmProviderTypeRaw, llmModel,
         nativeLanguageRaw, targetLanguageRaw].joined(separator: "|")
    }

    /// Settings ▸ Prompts, on a new module or this one.
    func openCustomModuleEditor(_ target: CustomModuleEditorTarget) {
        CustomModulesSection.requestEditor(target)
        settingsSelectedTab = SettingsTab.prompts.rawValue
        openSettings()
    }

    // MARK: Result

    func customResultView(_ module: CustomModule) -> some View {
        let output = viewModel.customOutputs[module.id] ?? ""
        let isLoading = viewModel.customLoading[module.id] == true
        let error = viewModel.customErrors[module.id]
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: module.icon)
                    .font(DS.Typography.icon(11, weight: .semibold))
                    .foregroundStyle(DS.Color.accent)
                Text(module.name)
                    .font(DS.Typography.subhead.weight(.semibold))
                    .lineLimit(1)
                    .layoutPriority(-1)
                if isLoading { liveStatusBadge }
                Spacer(minLength: 0)
                Text(module.length == .short ? "Short" : "Long")
                    .font(DS.Typography.caption2.weight(.semibold))
                    .foregroundStyle(DS.Color.textTertiary)
                    .help("Set in the module's settings")
                Button { runCustom(module, force: true) } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.dsIcon)
                .disabled(isLoading)
                .help("Refresh")
                Button { copyToClipboard(output, showFeedback: true) } label: {
                    Label("Copy result", systemImage: "doc.on.doc")
                }
                .buttonStyle(.dsIcon)
                .disabled(output.isEmpty)
                .help("Copy result")
                if isLoading {
                    Button { viewModel.cancelCustom(module.id) } label: {
                        Label("Cancel", systemImage: "xmark.circle.fill")
                    }
                    .buttonStyle(DSIconButtonStyle(tint: DS.Color.danger.opacity(0.78)))
                    .help("Cancel")
                }
            }
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.xs)
            .background(DS.Color.surfaceElevated)
            .overlay(alignment: .top) { Rectangle().fill(DS.Color.accent).frame(height: 2) }

            Group {
                if let error {
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(DS.Color.danger)
                            .font(DS.Typography.subhead)
                        Button("Retry") { runCustom(module, force: true) }
                            .buttonStyle(.bordered)
                    }
                    .padding(DS.Spacing.md)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else if output.isEmpty && !isLoading {
                    VStack(spacing: DS.Spacing.sm) {
                        Spacer()
                        Image(systemName: module.icon)
                            .font(DS.Typography.icon(24, weight: .light))
                            .foregroundStyle(DS.Color.textTertiary)
                        Text("Not asked yet.")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Color.textTertiary)
                        Button("Get") { runCustom(module, force: false) }
                            .buttonStyle(.bordered)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        Text(Self.markdown(output))
                            .font(DS.Typography.body)
                            .foregroundStyle(DS.Color.textPrimary)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(DS.Spacing.md)
                        if isLoading {
                            StreamingActivityIndicator()
                                .padding(.horizontal, DS.Spacing.md)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .background(DS.Color.cardInset)

            if !isLoading, error == nil, !output.isEmpty,
               let footer = customFooter(module.id) {
                AnswerFooterView(footer: footer, onExplain: openSpeedSettings)
            }
        }
        .dsPanel()
    }

    private func customFooter(_ id: UUID) -> AnswerFooter? {
        switch viewModel.customSources[id] {
        case .request(let request): return LLMRequestLog.shared.record(request).flatMap(AnswerFooter.make)
        case .cached: return .cached(engine: .provider(name: llmProviderTypeRaw, model: llmModel))
        case nil: return nil
        }
    }

    /// The answer as Markdown (inline styles and line breaks kept); the raw
    /// text when it doesn't parse.
    static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
