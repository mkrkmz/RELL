//
//  OnboardingView.swift
//  Reader for Language Learner
//
//  First-run flow: language pair → Apple Intelligence, when this Mac could
//  use it but it's off (v17 S3) → your AI provider, tested for speed → the
//  reading-loop tour (four pages, v14 S4). Skippable at any point; can be
//  reopened from Settings ▸ Data, and the tour alone from Help ▸ Reading Tour.
//

import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var step: Int

    init(startingAt step: Int = 0, onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        _step = State(initialValue: step)
    }
    /// Which edge the next step slides in from — flipped by Continue/Back so
    /// the transition always matches the direction the user is navigating.
    @State private var direction: Edge = .trailing
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage(Language.targetLanguageKey) private var targetRaw = Language.defaultTarget.rawValue
    @AppStorage(Language.nativeLanguageKey) private var nativeRaw = Language.defaultNative.rawValue
    /// Short meanings (word card, hover dictionary) — asked here, your own
    /// language first (1.47.1: a reader who chose Turkish saw English).
    @AppStorage(HoverDictionaryLanguage.storageKey) private var shortMeaningsRaw = HoverDictionaryLanguage.native.rawValue

    @State private var connectionStatus: OnboardingConnectionStatus = .idle

    @AppStorage(LLMConfiguration.providerTypeKey) private var providerTypeRaw = LLMConfiguration.defaultProviderType.rawValue
    @AppStorage(LLMConfiguration.serverURLKey) private var serverURL = LLMConfiguration.defaultServerURL
    @AppStorage(LLMConfiguration.modelKey) private var model = LLMConfiguration.defaultModel
    @State private var apiKey = LLMConfiguration.storedAPIKey

    /// Decided once: the step stays even after you turn it on.
    @State private var asksForAppleIntelligence = AppleOnDevice.couldBeReady
    /// Bumped by "Check Again" to read the model's state anew.
    @State private var appleCheck = 0

    private enum Step: Hashable {
        case language, appleIntelligence, server, tour(Int)
    }

    private var steps: [Step] {
        [.language] + (asksForAppleIntelligence ? [.appleIntelligence] : []) + [.server]
            + (0..<ReadingLoopTour.pageCount).map(Step.tour)
    }

    private var providerType: LLMProviderType {
        LLMProviderType(rawValue: providerTypeRaw) ?? .lmStudio
    }

    private var target: Language { Language(rawValue: targetRaw) ?? .english }
    private var native: Language { Language(rawValue: nativeRaw) ?? .turkish }

    private var stepCount: Int { steps.count }

    var body: some View {
        VStack(spacing: 0) {
            // Scrolls when a step is taller than the sheet (the provider
            // step with an API key field, large text sizes).
            ScrollView {
                Group {
                    switch steps[min(step, stepCount - 1)] {
                    case .language:          languageStep
                    case .appleIntelligence: appleIntelligenceStep
                    case .server:            serverStep
                    case .tour(let index):   ReadingLoopTourPage(index: index)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.horizontal, DS.Spacing.xxl)
                .padding(.vertical, DS.Spacing.xxl)
            }
            .scrollBounceBehavior(.basedOnSize)
            .id(step)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transition(stepTransition)
            .animation(DS.Animation.respecting(DS.Animation.spring, reduceMotion: reduceMotion), value: step)

            footer
        }
        .background(DS.Color.surface)
    }

    /// Slides in from `direction`; a plain fade when Reduce Motion is on.
    private var stepTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let exitEdge: Edge = direction == .trailing ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: direction).combined(with: .opacity),
            removal: .move(edge: exitEdge).combined(with: .opacity)
        )
    }

    // MARK: - Step 1: Language Pair

    private var languageStep: some View {
        VStack(spacing: DS.Spacing.xl) {
            stepHeader(
                icon: "book.pages",
                title: "Welcome to RELL",
                subtitle: "Read books and PDFs in the language you're learning and let AI explain every word in context."
            )

            HStack(spacing: DS.Spacing.lg) {
                languagePicker(role: "I'm learning", selection: $targetRaw, exclude: native)

                Image(systemName: "arrow.right")
                    .font(.title3.weight(.light))
                    .foregroundStyle(DS.Color.textTertiary)

                languagePicker(role: "My native language", selection: $nativeRaw, exclude: target)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: DS.Spacing.sm) {
                Text("SHORT MEANINGS")
                    .dsOverlineLabel()
                Picker("Short meanings", selection: $shortMeaningsRaw) {
                    Text(native.nativeName).tag(HoverDictionaryLanguage.native.rawValue)
                    Text(target.nativeName).tag(HoverDictionaryLanguage.target.rawValue)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)
                Text("The one-line meaning on the word card and in the hover dictionary.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
            }
            .onAppear {
                // Stored now, so the choice shown is the one used.
                if UserDefaults.standard.string(forKey: HoverDictionaryLanguage.storageKey) == nil {
                    shortMeaningsRaw = HoverDictionaryLanguage.native.rawValue
                }
            }

            Text("Definitions stay in \(target.nativeName); meanings and translations use \(native.nativeName). You can change this anytime in Settings.")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
    }

    private func languagePicker(role: String, selection: Binding<String>, exclude: Language) -> some View {
        VStack(spacing: DS.Spacing.sm) {
            Text(role.uppercased())
                .dsOverlineLabel()

            Picker(role, selection: selection) {
                ForEach(Language.allCases.filter { $0 != exclude }) { language in
                    Text("\(language.flag)  \(language.nativeName)").tag(language.rawValue)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 170)
        }
        .padding(DS.Spacing.lg)
        .dsCard(padding: nil, radius: DS.Radius.md, stroke: .hairline)
    }

    // MARK: - Apple Intelligence (v17 S3)

    private var appleIntelligenceStep: some View {
        let _ = appleCheck
        let ready = AppleOnDevice.isModelAvailable
        return VStack(spacing: DS.Spacing.xl) {
            stepHeader(
                icon: "apple.intelligence",
                title: "Turn On Apple Intelligence",
                subtitle: "This Mac can run Apple's on-device model. With it, definitions, meanings, examples and synonyms come in about a second — no setup, no internet, no cost."
            )

            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                HStack {
                    Text("Apple Intelligence")
                        .font(DS.Typography.callout.weight(.semibold))
                    Spacer()
                    Text(ready ? String(localized: "Ready") : (AppleOnDevice.unavailableReason ?? ""))
                        .font(DS.Typography.caption.weight(.semibold))
                        .foregroundStyle(ready ? DS.Color.success : DS.Color.warning)
                        .multilineTextAlignment(.trailing)
                }
                if !ready {
                    HStack(spacing: DS.Spacing.sm) {
                        Button("Open System Settings") {
                            NSWorkspace.shared.open(AppleOnDevice.appleIntelligenceSettingsURL)
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Check Again") { appleCheck += 1 }
                    }
                    Text("After you turn it on, the model can take a few minutes to download. RELL starts using it as soon as it's ready.")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: 420)
            .padding(DS.Spacing.xl)
            .dsCard(padding: nil, radius: DS.Radius.md, stroke: .hairline)
        }
    }

    // MARK: - AI Provider

    private var serverStep: some View {
        VStack(spacing: DS.Spacing.xl) {
            stepHeader(
                icon: "server.rack",
                title: "Connect your AI",
                subtitle: "Choose a provider for what Apple's model doesn't do — pronunciation, etymology, mnemonics, collocations and word family. A local server is private and free."
            )

            // With Apple's model there, the reader works before any server
            // exists; the server below adds the modules it isn't used for.
            if AppleOnDevice.currentRoute(for: nil) == .appleOnDevice {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple's on-device model is ready")
                            .font(DS.Typography.callout.weight(.semibold))
                        Text("Definitions, meanings, examples and synonyms work now, offline. A server adds pronunciation, etymology, mnemonics, collocations and word family.")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                } icon: {
                    Image(systemName: "apple.intelligence")
                        .foregroundStyle(DS.Color.success)
                }
                .frame(maxWidth: 440, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                Picker("Provider", selection: $providerTypeRaw) {
                    ForEach(LLMProviderType.allCases) { type in
                        Text(type.localizedTitle).tag(type.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: providerTypeRaw) { _, newValue in
                    guard let type = LLMProviderType(rawValue: newValue) else { return }
                    serverURL = type.defaultServerURL
                    model = type.defaultModel
                    connectionStatus = .idle
                }

                Grid(alignment: .leading, horizontalSpacing: DS.Spacing.sm, verticalSpacing: DS.Spacing.sm) {
                    GridRow {
                        Text("Server").foregroundStyle(DS.Color.textTertiary)
                        TextField(providerType.defaultServerURL, text: $serverURL)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("Model").foregroundStyle(DS.Color.textTertiary)
                        TextField(providerType.defaultModel, text: $model)
                            .textFieldStyle(.roundedBorder)
                    }
                    if providerType.requiresAPIKey {
                        GridRow {
                            Text("API Key").foregroundStyle(DS.Color.textTertiary)
                            SecureField("", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: apiKey) { _, newValue in
                                    LLMConfiguration.setAPIKey(newValue)
                                    NotificationCenter.default.post(name: .llmAPIKeyChanged, object: nil)
                                }
                        }
                    }
                }
                .font(DS.Typography.callout)
                .onChange(of: serverURL) { connectionStatus = .idle }
                .onChange(of: model) { connectionStatus = .idle }

                HStack(spacing: DS.Spacing.md) {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        if connectionStatus == .testing {
                            Label("Connecting…", systemImage: "circle.dotted")
                        } else {
                            Label("Test Connection", systemImage: "bolt")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(connectionStatus == .testing)

                    connectionFeedback
                }

                if LLMConfiguration().runsOnThisMac {
                    Text(SpeedAdvice.modelSizeHint(memoryBytes: ProcessInfo.processInfo.physicalMemory))
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: 460)
            .padding(DS.Spacing.xl)
            .dsCard(padding: nil, radius: DS.Radius.md, stroke: .hairline)

            Text("No server right now? Continue anyway — you can set up a provider later in Settings → AI.")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
    }

    @ViewBuilder
    private var connectionFeedback: some View {
        switch connectionStatus {
        case .idle:
            EmptyView()
        case .testing:
            ProgressView().controlSize(.small)
        case .success(let firstWord, let wordsPerSecond):
            let slow = LLMConfiguration().runsOnThisMac && (wordsPerSecond ?? .infinity) < SpeedAdvice.slowWordsPerSecond
            VStack(alignment: .leading, spacing: 2) {
                Label(speedLine(firstWord: firstWord, wordsPerSecond: wordsPerSecond),
                      systemImage: slow ? "tortoise.fill" : "checkmark.circle.fill")
                    .font(DS.Typography.caption.weight(.semibold))
                    .foregroundStyle(slow ? DS.Color.warning : DS.Color.success)
                if slow {
                    Text("This model is slow on this Mac. A smaller one answers faster.")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                }
            }
        case .failure(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.danger)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func speedLine(firstWord: TimeInterval?, wordsPerSecond: Double?) -> String {
        var parts = [String(localized: "Connected")]
        if let firstWord { parts.append(String(localized: "first word \(AnswerFooter.seconds(firstWord))")) }
        if let wordsPerSecond { parts.append(String(localized: "\(Int(wordsPerSecond.rounded())) words/s")) }
        return parts.joined(separator: " · ")
    }

    /// One short request, timed like the speed test: the first word (with
    /// any model load) and how fast it writes.
    private func testConnection() async {
        connectionStatus = .testing
        let configuration = LLMConfiguration()
        let provider = LLMRequestLog.shared.recording(configuration.makeProvider(), origin: .speedTest, route: .configured)
        var answer = ""
        do {
            try await provider.stream(system: SpeedTest.system, user: SpeedTest.prompt, temperature: 0,
                                      maxTokens: SpeedTest.maxTokens, topP: 1) { answer += $0 }
            let record = LLMRequestLog.shared.record(provider.id)
            connectionStatus = .success(
                firstWord: record?.firstToken,
                wordsPerSecond: record.flatMap { SpeedTest.wordsPerSecond(answer: answer, record: $0) }
            )
        } catch {
            connectionStatus = .failure(LLMErrorMessage.userMessage(for: error))
        }
    }

    // MARK: - Shared

    private func stepHeader(icon: String, title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        VStack(spacing: DS.Spacing.md) {
            ZStack {
                Circle()
                    .fill(DS.Color.accentSubtle)
                    .frame(width: 64, height: 64)
                Image(systemName: icon)
                    .font(DS.Typography.icon(26, weight: .light))
                    .foregroundStyle(DS.Color.accent)
            }

            VStack(spacing: DS.Spacing.xs) {
                Text(title)
                    .font(DS.Typography.title)
                    .foregroundStyle(DS.Color.textPrimary)
                Text(subtitle)
                    .font(DS.Typography.subhead)
                    .foregroundStyle(DS.Color.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 400)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: DS.Spacing.md) {
            if step < stepCount - 1 {
                Button("Skip", action: onFinish)
                    .buttonStyle(.borderless)
                    .foregroundStyle(DS.Color.textTertiary)
            }

            Spacer()

            ReadingLoopTourDots(current: step, count: stepCount)

            Spacer()

            if step > 0 {
                Button("Back") { direction = .leading; step -= 1 }
                    .buttonStyle(.bordered)
            }

            if step < stepCount - 1 {
                Button("Continue") { direction = .trailing; step += 1 }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Get Started", action: onFinish)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DS.Spacing.lg)
        .background(DS.Color.surfaceElevated.opacity(0.6))
    }
}

private enum OnboardingConnectionStatus: Equatable {
    case idle
    case testing
    case success(firstWord: TimeInterval?, wordsPerSecond: Double?)
    case failure(String)
}
