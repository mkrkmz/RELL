//
//  OnboardingView.swift
//  Reader for Language Learner
//
//  Three-step first-run flow: language pair → AI server check → quick tour.
//  Skippable at any point; can be reopened from Settings → General.
//

import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var step = 0
    /// Which edge the next step slides in from — flipped by Continue/Back so
    /// the transition always matches the direction the user is navigating.
    @State private var direction: Edge = .trailing
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage(Language.targetLanguageKey) private var targetRaw = Language.defaultTarget.rawValue
    @AppStorage(Language.nativeLanguageKey) private var nativeRaw = Language.defaultNative.rawValue

    @State private var connectionStatus: OnboardingConnectionStatus = .idle

    private var target: Language { Language(rawValue: targetRaw) ?? .english }
    private var native: Language { Language(rawValue: nativeRaw) ?? .turkish }

    private static let stepCount = 3

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0:  languageStep
                case 1:  serverStep
                default: tourStep
                }
            }
            .id(step)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, DS.Spacing.xxl)
            .padding(.top, DS.Spacing.xxl)
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
        .background(DS.Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .strokeBorder(DS.Color.hairline, lineWidth: 1)
        )
    }

    // MARK: - Step 2: AI Server

    private var serverStep: some View {
        VStack(spacing: DS.Spacing.xl) {
            stepHeader(
                icon: "server.rack",
                title: "Connect your AI",
                subtitle: "RELL uses a local LLM via LM Studio by default — private and free. Start LM Studio, load a model, and enable the local server."
            )

            VStack(spacing: DS.Spacing.md) {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "link")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Color.textTertiary)
                    Text(UserDefaults.standard.string(forKey: LLMConfiguration.serverURLKey) ?? LLMConfiguration.defaultServerURL)
                        .font(DS.Typography.mono)
                        .foregroundStyle(DS.Color.textSecondary)
                }

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
                .controlSize(.large)
                .disabled(connectionStatus == .testing)

                connectionFeedback
            }
            .frame(maxWidth: .infinity)
            .padding(DS.Spacing.xl)
            .background(DS.Color.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .strokeBorder(DS.Color.hairline, lineWidth: 1)
            )

            Text("No server right now? Continue anyway — you can set up a provider later in Settings → AI Provider.")
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
        case .success:
            Label("Connected — you're ready to read", systemImage: "checkmark.circle.fill")
                .font(DS.Typography.caption.weight(.semibold))
                .foregroundStyle(DS.Color.success)
        case .failure(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.danger)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
    }

    private func testConnection() async {
        connectionStatus = .testing
        let provider = LLMConfiguration().makeProvider()
        do {
            _ = try await provider.chat(
                system: "You are a test assistant.",
                user: "Reply with one word: OK",
                temperature: 0,
                maxTokens: 8,
                topP: 1
            )
            connectionStatus = .success
        } catch {
            connectionStatus = .failure(LLMErrorMessage.userMessage(for: error))
        }
    }

    // MARK: - Step 3: Quick Tour

    private var tourStep: some View {
        VStack(spacing: DS.Spacing.xl) {
            stepHeader(
                icon: "sparkles",
                title: "How RELL works",
                subtitle: "Three habits that build your vocabulary while you read."
            )

            VStack(spacing: DS.Spacing.md) {
                tourRow(
                    icon: "text.cursor",
                    title: "Select while reading",
                    detail: "Double-click any word for instant definitions, translations, and collocations."
                )
                tourRow(
                    icon: "star",
                    title: "Save the good ones",
                    detail: "Saved words enter a spaced-repetition queue with everything the AI explained."
                )
                tourRow(
                    icon: "flame",
                    title: "Review on the dashboard",
                    detail: "Flip the daily word card, keep your streak, and watch the goal ring fill."
                )
            }
        }
    }

    private func tourRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(DS.Color.accent)
                .frame(width: 30, height: 30)
                .background(DS.Color.accentSubtle)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(title)
                    .font(DS.Typography.label)
                    .foregroundStyle(DS.Color.textPrimary)
                Text(detail)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(DS.Spacing.md)
        .background(DS.Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .strokeBorder(DS.Color.separator.opacity(0.28), lineWidth: 1)
        )
    }

    // MARK: - Shared

    private func stepHeader(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: DS.Spacing.md) {
            ZStack {
                Circle()
                    .fill(DS.Color.accentSubtle)
                    .frame(width: 64, height: 64)
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .light))
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
            if step < Self.stepCount - 1 {
                Button("Skip", action: onFinish)
                    .buttonStyle(.borderless)
                    .foregroundStyle(DS.Color.textTertiary)
            }

            Spacer()

            HStack(spacing: DS.Spacing.xs) {
                ForEach(0..<Self.stepCount, id: \.self) { index in
                    Circle()
                        .fill(index == step ? DS.Color.accent : DS.Color.separator.opacity(0.5))
                        .frame(width: 6, height: 6)
                }
            }

            Spacer()

            if step > 0 {
                Button("Back") { direction = .leading; step -= 1 }
                    .buttonStyle(.bordered)
            }

            if step < Self.stepCount - 1 {
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
    case success
    case failure(String)
}
