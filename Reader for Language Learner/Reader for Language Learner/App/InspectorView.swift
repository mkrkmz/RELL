//
//  InspectorView.swift
//  Reader for Language Learner
//

import AppKit
import SwiftUI

// MARK: - InspectorView

struct InspectorView: View {
    let selectedText: String
    let contextSentence: String?
    let pdfFilename: String?
    let pageNumber: Int?
    var savedWordsStore: SavedWordsStore

    // MARK: State

    @State var viewModel = InspectorViewModel()
    @State var explainMode: ExplainMode = .word
    @State var explainDetail: ExplainDetail = .short
    @AppStorage("domainPreference") var domainRaw: String = DomainPreference.general.rawValue
    var domainPreference: DomainPreference {
        DomainPreference(rawValue: domainRaw) ?? .general
    }
    @State var activeModule: ModuleType?
    @State var voiceOption: VoiceOption = .englishUS
    @State var speechRate: Double = 0.5
    @State var lastUsedModule: ModuleType = .definitionEN
    @State var showAnkiExport = false
    @State var showToast      = false
    @State var toastMessage   = ""
    @State var moduleStartTimes: [ModuleType: Date] = [:]
    @State var moduleElapsed: [ModuleType: Double] = [:]
    @State var displayedText: String = ""
    @State var selectionDebounceTask: Task<Void, Never>?

    @State var circuitBreaker = CircuitBreaker()
    @Namespace var moduleNamespace

    @AppStorage(LLMConfiguration.providerTypeKey) var llmProviderTypeRaw: String = LLMConfiguration.defaultProviderType.rawValue
    @AppStorage(LLMConfiguration.serverURLKey)    var llmServerURL: String = LLMConfiguration.defaultServerURL
    @AppStorage(LLMConfiguration.modelKey)        var llmModel: String     = LLMConfiguration.defaultModel
    @AppStorage(LLMConfiguration.timeoutKey)      var llmTimeout: Double   = LLMConfiguration.defaultTimeout
    @AppStorage(LLMConfiguration.apiKeyKey)       var llmAPIKey: String    = ""
    @AppStorage(Language.nativeLanguageKey)    var nativeLanguageRaw: String = Language.defaultNative.rawValue
    @Environment(AnkiModulePreferences.self) var ankiPrefs

    var speechManager: SpeechManager { SpeechManager.shared }
    @Environment(\.openSettings) var openSettings

    let primaryModules:  [ModuleType] = [.definitionEN, .meaningTR, .collocations, .examplesEN, .pronunciationEN]
    let overflowModules: [ModuleType] = [.etymologyEN, .mnemonicEN, .synonymsEN, .wordFamilyEN, .usageNotesEN]

    var nativeLanguage: Language {
        Language(rawValue: nativeLanguageRaw) ?? .turkish
    }

    var llmProvider: any LLMProvider {
        ResilientLLMProvider(
            provider: LLMConfiguration().makeProvider(),
            circuitBreaker: circuitBreaker
        )
    }

    var trimmedSelection: String {
        displayedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasSelection: Bool { !trimmedSelection.isEmpty }

    // MARK: - Body

    var body: some View {
        ZStack {
            VisualEffectView(material: .contentBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if circuitBreaker.state == .open {
                    connectionWarningBanner
                }

                if hasSelection {
                    selectionContent
                        .transition(.opacity)
                } else {
                    emptyState
                        .transition(.opacity)
                }
            }
        }
        .animation(DS.Animation.standard, value: hasSelection)
        .onExitCommand { activeModule = nil }
        .onChange(of: selectedText) { _, newText in
            speechManager.stop()
            selectionDebounceTask?.cancel()
            selectionDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(90))
                guard !Task.isCancelled else { return }
                displayedText = newText
                viewModel.resetAll()
                let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { refreshCache(term: trimmed) }
                else { activeModule = nil }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .inspectorRunLastModule)) { _ in
            guard hasSelection else { return }
            focusAndRunLast()
        }
        .onChange(of: explainMode)  { _, _ in refreshCache(term: trimmedSelection) }
        .onChange(of: explainDetail){ _, _ in refreshCache(term: trimmedSelection) }
        .onChange(of: domainRaw)    { _, _ in
            viewModel.outputs[.collocations] = nil
            viewModel.errors[.collocations]  = nil
            refreshCache(term: trimmedSelection)
        }
        .onChange(of: nativeLanguageRaw) { _, _ in
            // Native language change invalidates meaningTR and collocations outputs
            viewModel.outputs[.meaningTR]    = nil
            viewModel.outputs[.collocations] = nil
            viewModel.errors[.meaningTR]     = nil
            viewModel.errors[.collocations]  = nil
            viewModel.cache.removeAll()
            refreshCache(term: trimmedSelection)
        }
        .sheet(isPresented: $showAnkiExport) {
            AnkiExportView(
                selectedText: trimmedSelection,
                mode: explainMode,
                domain: domainPreference,
                outputs: viewModel.outputs,
                pdfFilename: pdfFilename,
                pageNumber: pageNumber,
                contextSentence: contextSentence
            )
        }
    }

    // MARK: - Empty State

    var emptyState: some View {
        VStack(spacing: DS.Spacing.lg) {
            Spacer()

            ZStack {
                Circle()
                    .fill(DS.Color.accentSubtle)
                    .frame(width: 72, height: 72)
                Image(systemName: "text.cursor")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(DS.Color.accent)
            }

            VStack(spacing: DS.Spacing.xs) {
                Text("Select text to analyze")
                    .font(DS.Typography.headline)
                    .foregroundStyle(DS.Color.textPrimary)
                Text("Double-click a word or drag\nto select a sentence.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Selection Content

    var selectionContent: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            selectionHeader
            modeBar
            moduleGrid
            Divider().padding(.horizontal, DS.Spacing.xs)
            resultPanel
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dsToast(isPresented: $showToast, message: toastMessage)
    }

    // MARK: - Mode Bar (Word / Sentence)

    var modeBar: some View {
        HStack(spacing: DS.Spacing.xs) {
            ForEach(ExplainMode.allCases) { mode in
                Button { explainMode = mode } label: {
                    Text(mode.rawValue)
                        .font(DS.Typography.caption.weight(explainMode == mode ? .semibold : .regular))
                        .foregroundStyle(explainMode == mode ? DS.Color.accent : DS.Color.textSecondary)
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, DS.Spacing.xs)
                        .background {
                            if explainMode == mode {
                                Capsule()
                                    .fill(DS.Color.accentSubtle)
                                    .matchedGeometryEffect(id: "modeBackground", in: moduleNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Detail toggle
            Button {
                explainDetail = explainDetail == .short ? .detailed : .short
            } label: {
                Label(
                    explainDetail == .short ? "Short" : "Detailed",
                    systemImage: explainDetail == .short ? "text.alignleft" : "text.alignjustify"
                )
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.textSecondary)
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.vertical, DS.Spacing.xs)
                .background(DS.Color.surfaceElevated)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Toggle output length")
        }
        .animation(DS.Animation.springFast, value: explainMode)
    }

    // MARK: - Connection Warning

    private var connectionWarningBanner: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("LLM server unreachable")
                .font(DS.Typography.caption)
            Spacer()
            Button("Retry") {
                circuitBreaker.reset()
            }
            .font(DS.Typography.caption)
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
        .background(Color.orange.opacity(0.1))
    }

    // MARK: - Helpers

    func iconButton(
        systemImage: String,
        help: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    func actionSpacer() -> some View {
        Divider()
            .frame(height: 14)
            .padding(.horizontal, DS.Spacing.xxs)
    }

    var isAnyLoading: Bool {
        viewModel.loading.values.contains(true)
    }

    func isModuleEnabled(_ module: ModuleType) -> Bool {
        guard hasSelection else { return false }
        guard module.isEnabled(mode: explainMode) else { return false }
        return viewModel.loading[module] != true
    }

    func refreshCache(term: String) {
        viewModel.resetAll()
        guard !term.isEmpty else { return }
        let key = OutputCacheKey(
            term: term, mode: explainMode.rawValue,
            detail: explainDetail.rawValue, domain: domainPreference.rawValue
        )
        let loaded = viewModel.loadFromCache(key: key)
        if !loaded, let activeModule, !activeModule.isEnabled(mode: explainMode) {
            self.activeModule = nil
        }
    }

    func toggleModule(_ module: ModuleType) {
        if activeModule == module { activeModule = nil; return }
        activeModule = module
        lastUsedModule = module
        if (viewModel.outputs[module] ?? "").isEmpty {
            Task { await runModule(module, forceRefresh: false) }
        }
    }

    func focusAndRunLast() {
        activeModule = lastUsedModule
        if (viewModel.outputs[lastUsedModule] ?? "").isEmpty {
            Task { await runModule(lastUsedModule, forceRefresh: false) }
        }
    }

    @MainActor
    func runModule(_ module: ModuleType, forceRefresh: Bool) async {
        guard module.isEnabled(mode: explainMode), hasSelection else { return }
        if !forceRefresh, let cached = viewModel.outputs[module], !cached.isEmpty { return }

        viewModel.cancel(module: module)
        moduleStartTimes[module] = Date()
        moduleElapsed[module] = nil
        viewModel.loading[module] = true
        viewModel.errors[module]  = nil
        viewModel.outputs[module] = ""

        let client       = llmProvider
        let systemPrompt = module.systemPrompt
        let userPrompt   = module.userPrompt(
            term: trimmedSelection,
            mode: explainMode,
            detail: explainDetail,
            domain: domainPreference,
            context: contextSentence,
            nativeLanguage: nativeLanguage
        )
        let cacheKey = OutputCacheKey(
            term: trimmedSelection, mode: explainMode.rawValue,
            detail: explainDetail.rawValue, domain: domainPreference.rawValue
        )

        let task = Task { @MainActor in
            do {
                try await client.stream(
                    system: systemPrompt,
                    user: userPrompt,
                    temperature: module.recommendedTemperature,
                    maxTokens: module.recommendedMaxTokens(mode: explainMode, detail: explainDetail),
                    topP: 0.9
                ) { token in
                    self.viewModel.outputs[module, default: ""] += token
                }
            } catch {
                if !Task.isCancelled { viewModel.errors[module] = error.localizedDescription }
            }

            if !Task.isCancelled { viewModel.snapshotToCache(key: cacheKey) }
            if let start = moduleStartTimes[module] {
                moduleElapsed[module] = Date().timeIntervalSince(start)
            }
            viewModel.loading[module] = false
            viewModel.activeTasks[module] = nil
        }
        viewModel.activeTasks[module] = task
    }

    func showToastBriefly(_ message: String, variant: DSToast.Variant = .success) {
        toastMessage = message
        showToast    = true         // DSToastModifier auto-dismisses
    }

    func copyToClipboard(_ text: String, showFeedback: Bool = false) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        if showFeedback { showToastBriefly("Copied!") }
    }

    func speakSelection() {
        guard hasSelection else { return }
        speechManager.speak(trimmedSelection, voice: voiceOption, rate: Float(speechRate))
    }

    func toggleSaveWord() {
        guard hasSelection else { return }
        if isCurrentlySaved {
            savedWordsStore.remove(term: trimmedSelection, pdfFilename: pdfFilename, pageNumber: pageNumber)
            showToastBriefly("Removed")
        } else {
            var outputs: [String: String] = [:]
            for (module, output) in viewModel.outputs {
                let cleaned = output.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty { outputs[module.rawValue] = cleaned }
            }
            savedWordsStore.add(SavedWord(
                term: trimmedSelection,
                sentence: contextSentence ?? "",
                pdfFilename: pdfFilename,
                pageNumber: pageNumber,
                mode: explainMode.rawValue,
                domain: domainPreference.rawValue,
                llmOutputs: outputs
            ))
            showToastBriefly("Word saved!")
        }
    }

    @MainActor
    func quickExport() async {
        let selected = ankiPrefs.selectedModules(from: viewModel.outputs)

        let note = AnkiExporter.buildNote(
            selectedText: trimmedSelection, mode: explainMode, domain: domainPreference,
            selectedModules: selected, outputs: viewModel.outputs,
            includeSource: ankiPrefs.includeSource, pdfFilename: pdfFilename,
            pageNumber: pageNumber, contextSentence: contextSentence, tags: ankiPrefs.tags
        )
        let content = AnkiExporter.tsvDocument(from: note)
        guard await AnkiExporter.saveTSV(content: content) else { return }

        showToastBriefly("Exported to Anki!")
    }


}

// MARK: - View Conditional Modifier

extension View {
    @ViewBuilder
    func `if`<Transform: View>(
        _ condition: Bool,
        transform: (Self) -> Transform
    ) -> some View {
        if condition { transform(self) }
        else { self }
    }
}

// MARK: - PulsingDot (legacy — kept for compatibility)

struct PulsingDot: View {
    @State var scale: CGFloat = 0.6
    var body: some View {
        Circle()
            .fill(DS.Color.accent)
            .frame(width: 7, height: 7)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    scale = 1.0
                }
            }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let inspectorRunLastModule = Notification.Name("inspectorRunLastModule")
}
