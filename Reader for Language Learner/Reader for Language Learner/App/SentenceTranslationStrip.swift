//
//  SentenceTranslationStrip.swift
//  Reader for Language Learner
//
//  Thin bar below the PDF showing a native-language translation of the
//  currently selected sentence. Cache-first; then Apple Translation when the
//  pair is supported (v1.40), otherwise — or if it fails — the AI provider
//  via QuickLookupService.
//

import SwiftUI
import Translation

struct SentenceTranslationStrip: View {
    let sentence: String
    var service: QuickLookupService
    let onClose: () -> Void

    @State private var phase: Phase = .loading
    /// Non-nil hands the current sentence to Apple Translation.
    @State private var appleConfiguration: TranslationSession.Configuration?

    enum Phase: Equatable {
        case loading
        case loaded(String)
        case failed
    }

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            Image(systemName: "character.bubble")
                .font(DS.Typography.icon(12, weight: .semibold))
                .foregroundStyle(DS.Color.accent)
                .padding(.top, 1)

            content

            Spacer(minLength: DS.Spacing.sm)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(DS.Typography.icon(10, weight: .semibold))
                    .foregroundStyle(DS.Color.textTertiary)
            }
            .buttonStyle(.plain)
            .help("Hide translation")
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
        // A floating bar over the reader — chrome, so it takes glass on macOS 26.
        .dsGlassCard(
            radius: DS.Radius.sm,
            fallback: AnyShapeStyle(DS.Color.surfaceElevated),
            fallbackStroke: .hairline
        )
        .task(id: sentence) { await load() }
        .translationTask(appleConfiguration) { [sentence] session in
            // The session lives only for this closure and is used by nothing
            // else, so handing it to its own nonisolated `translate` can't
            // race; the SDK just doesn't mark it Sendable.
            nonisolated(unsafe) let session = session
            let translated = try? await session.translate(sentence).targetText
            await applyAppleTranslation(translated, for: sentence)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            HStack(spacing: DS.Spacing.sm) {
                ProgressView().controlSize(.small)
                Text("Translating…")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
            }
        case .loaded(let translation):
            Text(translation)
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Color.textPrimary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        case .failed:
            Text("Couldn't translate — check your AI server.")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.textTertiary)
        }
    }

    private func load() async {
        if let cached = service.cachedTranslation(for: sentence) {
            phase = .loaded(cached)
            return
        }
        phase = .loading
        if SentenceTranslationEngine.stored == .apple,
           await AppleTranslation.canTranslate(from: Language.storedTarget, to: Language.storedNative) {
            let source = AppleTranslation.localeLanguage(for: Language.storedTarget)
            let target = AppleTranslation.localeLanguage(for: Language.storedNative)
            if appleConfiguration?.source == source, appleConfiguration?.target == target {
                appleConfiguration?.invalidate()   // same pair, new sentence: run again
            } else {
                appleConfiguration = TranslationSession.Configuration(source: source, target: target)
            }
            return
        }
        await translateWithAIProvider()
    }

    /// `nil` means Apple couldn't: a declined download, a missing pack or
    /// text it won't take. The AI provider still gets a chance.
    private func applyAppleTranslation(_ translation: String?, for translated: String) async {
        guard translated == sentence else { return }
        guard let translation else {
            await translateWithAIProvider()
            return
        }
        service.storeTranslation(translation, for: translated)
        phase = .loaded(translation)
    }

    private func translateWithAIProvider() async {
        do {
            let translation = try await service.translate(sentence: sentence)
            phase = .loaded(translation)
        } catch {
            phase = .failed
        }
    }
}
