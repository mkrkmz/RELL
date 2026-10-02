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
    /// Owned by ContentView so the toolbar status item shares the same instance.
    var circuitBreaker: CircuitBreaker

    // MARK: State

    @State var viewModel = InspectorViewModel()
    @State var explainMode: ExplainMode = .word
    @State var explainDetail: ExplainDetail = .short
    /// Set when the mode changed with the selection (`adoptAutomaticMode`):
    /// the selection handler reloads the cache itself, and a second reload
    /// from the mode's onChange would cancel the auto-run it just started.
    @State var modeChangedWithSelection = false
    @AppStorage(StorageKey.domainPreference) var domainRaw: String = DomainPreference.general.rawValue
    var domainPreference: DomainPreference {
        DomainPreference(rawValue: domainRaw) ?? .general
    }
    @State var activeModule: ModuleType?
    @AppStorage(StorageKey.speechRate) var speechRate: Double = 0.5
    @State var lastUsedModule: ModuleType = .definitionEN
    @State var showAnkiExport = false
    @State var showToast      = false
    @State var toastMessage   = ""
    @State var displayedText: String = ""
    @State var followUpQuestion: String = ""
    @State var selectionDebounceTask: Task<Void, Never>?
    /// Last auto-scroll during streaming — throttles scroll-to-bottom to ~6/s.
    @State var lastStreamScrollAt: Date = .distantPast
    @AppStorage(StorageKey.autoRunEnabled) var autoRunEnabled: Bool = true
    @AppStorage(StorageKey.inspectorFollowsPageTheme) var inspectorFollowsPageTheme = false
    @AppStorage(StorageKey.pageTheme) var pageThemeRaw = PageTheme.original.rawValue
    @Environment(\.colorScheme) private var systemColorScheme

    @Namespace var moduleNamespace

    @AppStorage(LLMConfiguration.providerTypeKey) var llmProviderTypeRaw: String = LLMConfiguration.defaultProviderType.rawValue
    @AppStorage(LLMConfiguration.serverURLKey)    var llmServerURL: String = LLMConfiguration.defaultServerURL
    @AppStorage(LLMConfiguration.modelKey)        var llmModel: String     = LLMConfiguration.defaultModel
    @AppStorage(LLMConfiguration.timeoutKey)      var llmTimeout: Double   = LLMConfiguration.defaultTimeout
    @AppStorage(Language.nativeLanguageKey)    var nativeLanguageRaw: String = Language.defaultNative.rawValue
    @AppStorage(Language.targetLanguageKey)    var targetLanguageRaw: String = Language.defaultTarget.rawValue
    @Environment(AnkiModulePreferences.self) var ankiPrefs
    @Environment(QuickLookupService.self) var quickLookup
    @Environment(WordEncounterStore.self) var encounterStore: WordEncounterStore?
    /// One-line meaning on the word card (v13 Sprint 3).
    @State var inspectorQuickMeaning: String?
    @Environment(\.openSettings) private var openSettings
    @AppStorage(StorageKey.settingsSelectedTab) private var settingsSelectedTab = SettingsTab.general.rawValue

    var speechManager: SpeechManager { SpeechManager.shared }

    let primaryModules:  [ModuleType] = ModuleType.primary

    var nativeLanguage: Language {
        Language(rawValue: nativeLanguageRaw) ?? .turkish
    }

    var targetLanguage: Language {
        Language(rawValue: targetLanguageRaw) ?? .english
    }

    /// The provider for `module` (nil: free-form work such as Ask AI).
    /// Apple's on-device model is used directly — retries and the circuit
    /// breaker exist for a network server, and an on-device failure must not
    /// mark the configured server as down.
    func llmProvider(for module: ModuleType?) -> any LLMProvider {
        let provider = AppleOnDevice.provider(for: module)
        guard AppleOnDevice.currentRoute(for: module) == .configured else { return provider }
        return ResilientLLMProvider(provider: provider, circuitBreaker: circuitBreaker)
    }

    /// Provider part of the output cache key. Apple's layer changes which
    /// model answers some modules, so it's part of the key: turning it on or
    /// off never serves the other model's answers.
    var cacheProviderLabel: String {
        AppleOnDevice.currentRoute(for: nil) == .appleOnDevice
            ? "\(llmProviderTypeRaw)+\(AppleOnDevice.providerLabel)"
            : llmProviderTypeRaw
    }

    var trimmedSelection: String {
        displayedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasSelection: Bool { !trimmedSelection.isEmpty }

    // MARK: - Body

    // Staged like ContentView.body — a single 24-modifier chain here would
    // risk the same "unable to type-check this expression in reasonable
    // time" CI failure that ContentView hit (see CHANGELOG v1.9.0 fix).
    var body: some View {
        withSheets(withPreferenceSync(withNotifications(withSelectionLifecycle(baseContent))))
    }

    /// The page theme's tones when "follows the page theme" is on (v14 S2).
    private var followedPageSurface: (fill: SwiftUI.Color, isDark: Bool)? {
        guard inspectorFollowsPageTheme else { return nil }
        return (PageTheme(rawValue: pageThemeRaw) ?? .original).inspectorSurface
    }

    @ViewBuilder
    private var inspectorBackground: some View {
        if let surface = followedPageSurface {
            surface.fill.ignoresSafeArea()
        } else {
            VisualEffectView(material: .contentBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
        }
    }

    // One tree whatever the setting — only the background and the colour
    // scheme change, so toggling it keeps the panel's state.
    private var baseContent: some View {
        ZStack {
            inspectorBackground

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
        .environment(\.colorScheme, followedPageSurface.map { $0.isDark ? .dark : .light } ?? systemColorScheme)
    }

    private func withSelectionLifecycle(_ content: some View) -> some View {
        content
            .onAppear {
                // A fresh mount (inspector toggled back on) starts with empty
                // @State — adopt the live selection so the panel isn't blank
                // and menu-driven module runs can proceed.
                displayedText = selectedText
                let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    adoptAutomaticMode(for: trimmed)
                    refreshCache(term: trimmed)
                }
            }
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
                    if !trimmed.isEmpty {
                        adoptAutomaticMode(for: trimmed)
                        refreshCache(term: trimmed)
                        viewModel.addToRecents(trimmed)
                        // Auto-run: if cache missed (no outputs loaded) and feature is on, trigger last module
                        if autoRunEnabled && viewModel.outputs.isEmpty {
                            let module = lastUsedModule
                            if module.isEnabled(mode: explainMode) {
                                activeModule = module
                                Task { await runModule(module, forceRefresh: false) }
                            }
                        }
                    } else {
                        activeModule = nil
                    }
                }
            }
    }

    private func withNotifications(_ content: some View) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .inspectorRunLastModule)) { _ in
                guard hasSelection else { return }
                focusAndRunLast()
            }
            .onReceive(NotificationCenter.default.publisher(for: .inspectorRunModule)) { note in
                guard let raw = note.object as? String,
                      let module = ModuleType(rawValue: raw),
                      hasSelection,
                      module.isEnabled(mode: explainMode)
                else { return }
                activeModule = module
                lastUsedModule = module
                if (viewModel.outputs[module] ?? "").isEmpty {
                    Task { await runModule(module, forceRefresh: false) }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .inspectorRecentTermSelected)) { note in
                guard let term = note.object as? String else { return }
                displayedText = term
                viewModel.resetAll()
                adoptAutomaticMode(for: term)
                refreshCache(term: term)
                viewModel.addToRecents(term)
                if autoRunEnabled && viewModel.outputs.isEmpty {
                    let module = lastUsedModule
                    if module.isEnabled(mode: explainMode) {
                        activeModule = module
                        Task { await runModule(module, forceRefresh: false) }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .inspectorToggleSaveWord)) { _ in
                toggleSaveWord()
            }
    }

    private func withPreferenceSync(_ content: some View) -> some View {
        content
            .onChange(of: explainMode)  { _, _ in
                if modeChangedWithSelection {
                    modeChangedWithSelection = false
                    return
                }
                refreshCache(term: trimmedSelection)
            }
            .onChange(of: explainDetail){ _, _ in refreshCache(term: trimmedSelection) }
            .onChange(of: domainRaw)    { _, _ in
                viewModel.outputs[.collocations] = nil
                viewModel.errors[.collocations]  = nil
                refreshCache(term: trimmedSelection)
            }
            .onChange(of: nativeLanguageRaw) { _, _ in
                // Native language is part of the cache key — old entries stay
                // valid under their own key; just reload for the new one.
                refreshCache(term: trimmedSelection)
            }
            .onChange(of: targetLanguageRaw) { _, _ in
                // Target language is part of the cache key too.
                refreshCache(term: trimmedSelection)
            }
            .onChange(of: llmProviderTypeRaw) { _, _ in
                // Provider is part of the cache key — no wipe needed.
                circuitBreaker.reset()
                refreshCache(term: trimmedSelection)
            }
            .onChange(of: llmModel) { _, _ in
                // Model is part of the cache key — no wipe needed.
                circuitBreaker.reset()
                refreshCache(term: trimmedSelection)
            }
            .onChange(of: llmServerURL) { _, _ in
                // Server URL is NOT in the cache key: a different server behind
                // the same model name may answer differently, so wipe.
                circuitBreaker.reset()
                viewModel.clearCache()
                refreshCache(term: trimmedSelection)
            }
            .onReceive(NotificationCenter.default.publisher(for: .llmAPIKeyChanged)) { _ in
                // Key lives in the Keychain now — settings announces changes
                // since there's no @AppStorage value left to observe.
                circuitBreaker.reset()
            }
            .onChange(of: llmTimeout) { _, _ in
                circuitBreaker.reset()
            }
    }

    private func withSheets(_ content: some View) -> some View {
        content
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
        DSEmptyState(
            icon: "text.cursor",
            title: "Select text to analyze",
            message: "Double-click a word or drag\nto select a sentence."
        )
    }

    // MARK: - Selection Content

    /// The inspector as it's laid out when it fits, and — when the window is
    /// too short for it — the same content in one scroll view with the
    /// result panel at a fixed height. Without the fallback the top zone
    /// (word card, controls, module grid) set a minimum height taller than a
    /// minimum-size window allows (638 pt against ~548), and AppKit looped
    /// on its constraints — the crash v13's live pass hit. Guarded by
    /// `LayoutGuardTests` (v14 Sprint 0).
    var selectionContent: some View {
        ViewThatFits(in: .vertical) {
            selectionStack(resultHeight: nil)
            ScrollView {
                selectionStack(resultHeight: Self.compactResultHeight)
            }
        }
    }

    /// Result panel height when the whole inspector scrolls.
    static let compactResultHeight: CGFloat = 260

    private func selectionStack(resultHeight: CGFloat?) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            // v14 S2 — first the selection and what you can do with it, then
            // depth. ── Zone 1: word or sentence card, with its actions ──────
            selectionHeader

            // ── Zone 2: passage tools (phrase or sentence only) ──────────────
            if !isSingleWordSelection {
                sentenceTools
            }

            // ── Zone 3: explanations ─────────────────────────────────────────
            moduleGrid

            // ── Zone 4: result — the one zone that stretches ─────────────────
            resultPanel
                .frame(height: resultHeight)

            // ── Zone 5: ask a follow-up ──────────────────────────────────────
            askAISection
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dsToast(isPresented: $showToast, message: toastMessage)
    }

    // MARK: - Connection Warning

    private var connectionWarningBanner: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DS.Color.warning)
            Text("LLM server unreachable")
                .font(DS.Typography.caption)
            Spacer()
            Button("Retry") {
                circuitBreaker.reset()
            }
            .font(DS.Typography.caption)
            .buttonStyle(.borderless)
            Button("Settings…") {
                settingsSelectedTab = SettingsTab.llm.rawValue
                openSettings()
            }
            .font(DS.Typography.caption)
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
        // A warning-tinted glass strip on macOS 26 (meaning-carrying tint, not
        // decoration); the flat warningSubtle wash on macOS 15. radius 0 keeps
        // it a full-width banner rather than a floating card.
        .dsGlassCard(
            radius: 0,
            tint: DS.Color.warning,
            fallback: AnyShapeStyle(DS.Color.warningSubtle),
            fallbackStroke: .none
        )
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
                .font(DS.Typography.icon(12, weight: .medium))
                .frame(width: 28, height: 28)
                .dsGlassInteractive(cornerRadius: DS.Radius.sm)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .opacity(role == .destructive ? 0.94 : 1)
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
            detail: explainDetail.rawValue, domain: domainPreference.rawValue,
            provider: cacheProviderLabel, model: llmModel,
            native: nativeLanguageRaw, target: targetLanguageRaw
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

        let route = AppleOnDevice.currentRoute(for: module)
        let customPreamble = UserDefaults.standard.string(forKey: StorageKey.customSystemPreamble) ?? ""

        // Temperature override from Prompt settings if set, otherwise module default.
        let temperature: Double = {
            guard let data = UserDefaults.standard.string(forKey: StorageKey.temperatureOverrides)?.data(using: .utf8),
                  let overrides = try? JSONDecoder().decode([String: Double].self, from: data),
                  let custom = overrides[module.rawValue]
            else { return module.recommendedTemperature }
            return custom
        }()

        let run = InspectorViewModel.ModuleRun(
            module: module,
            system: module.systemPrompt(
                customPreamble: customPreamble,
                nativeLanguage: nativeLanguage,
                targetLanguage: targetLanguage
            ),
            user: module.userPrompt(
                term: trimmedSelection,
                mode: explainMode,
                detail: explainDetail,
                domain: domainPreference,
                context: contextSentence,
                nativeLanguage: nativeLanguage,
                targetLanguage: targetLanguage
            ),
            temperature: temperature,
            maxTokens: module.recommendedMaxTokens(mode: explainMode, detail: explainDetail, modelIdentifier: llmModel),
            cacheKey: OutputCacheKey(
                term: trimmedSelection, mode: explainMode.rawValue,
                detail: explainDetail.rawValue, domain: domainPreference.rawValue,
                provider: cacheProviderLabel, model: llmModel,
                native: nativeLanguageRaw, target: targetLanguageRaw
            ),
            isFallback: AppleOnDevice.isFallback(module),
            // Local servers process requests on one GPU context — running many
            // streams at once slows all of them, so gate their concurrency.
            usesLocalGate: route == .configured && configuredProviderIsLocal
        )
        viewModel.start(run, provider: llmProvider(for: module))
    }

    /// LM Studio / Ollama — the servers `localRequestGate` exists for.
    var configuredProviderIsLocal: Bool {
        llmProviderTypeRaw == LLMProviderType.lmStudio.rawValue
            || llmProviderTypeRaw == LLMProviderType.ollama.rawValue
    }

    /// Word or sentence from the selection itself (v14 S2; before, a
    /// switch the reader flipped by hand — still in the overflow menu).
    /// Call before the caller's own cache reload; the mode's onChange then
    /// skips its reload (see `modeChangedWithSelection`).
    func adoptAutomaticMode(for selection: String) {
        let mode = ExplainMode.automatic(for: selection)
        guard explainMode != mode else { return }
        modeChangedWithSelection = true
        explainMode = mode
    }

    func runAllPrimaryModules() {
        for module in primaryModules where module.isEnabled(mode: explainMode) {
            if (viewModel.outputs[module] ?? "").isEmpty {
                Task { await runModule(module, forceRefresh: false) }
            }
        }
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
        speechManager.speak(trimmedSelection, language: Language.storedTarget, rate: Float(speechRate))
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
                llmOutputs: outputs,
                language: targetLanguage.rawValue
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
                withAnimation(DS.Animation.pulse) {
                    scale = 1.0
                }
            }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let inspectorRunLastModule    = Notification.Name("inspectorRunLastModule")
    static let inspectorRecentTermSelected = Notification.Name("inspectorRecentTermSelected")
    /// Runs a specific module; `object` is the `ModuleType` raw value.
    static let inspectorRunModule        = Notification.Name("inspectorRunModule")
    /// Posted by the Save Word menu command (and ⌘D once routed through the
    /// menu bridge) — the panel must be mounted to reach `viewModel.outputs`.
    static let inspectorToggleSaveWord   = Notification.Name("inspectorToggleSaveWord")
}
