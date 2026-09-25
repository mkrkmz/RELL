//
//  AppleOnDevice.swift
//  Reader for Language Learner
//
//  Apple's on-device model (FoundationModels, macOS 26+) as a layer in front
//  of the configured provider — zero setup, offline, free. It answers only
//  the modules it gets right; the rest go to the configured provider.
//
//  The split comes from the v12 spike (RELL's real prompts, five language
//  pairs, median 0.9 s): definitions, native meaning, examples, synonyms and
//  usage notes were sound; IPA outside English was wrong, etymology was
//  invented ("Verständnis comes from Latin"), mnemonics were nonsense, and
//  collocations / word family were shaky (a made-up "resiliencing"). The
//  model supports 10 of RELL's 12 languages — not Arabic or Russian.
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Where one request goes.
enum LLMRoute: Equatable {
    case appleOnDevice
    case configured
}

enum AppleOnDevice {
    /// `@AppStorage` key for the Settings toggle. On by default: when the
    /// model is there, a new user gets answers without installing anything.
    static let enabledKey = "appleOnDeviceEnabled"
    static let providerLabel = "Apple On-Device"

    /// Modules the spike found reliable on the on-device model.
    static let reliableModules: Set<ModuleType> = [
        .definitionEN, .meaningTR, .examplesEN, .synonymsEN, .usageNotesEN,
    ]

    // MARK: Routing (pure)

    /// `module == nil` is free-form work (Ask AI, sentence translation, CEFR
    /// estimate), which the model handles well.
    static func route(
        for module: ModuleType?,
        enabled: Bool,
        modelAvailable: Bool,
        languagesSupported: Bool
    ) -> LLMRoute {
        guard enabled, modelAvailable, languagesSupported else { return .configured }
        guard let module else { return .appleOnDevice }
        return reliableModules.contains(module) ? .appleOnDevice : .configured
    }

    /// The live route for `module` with the stored settings.
    @MainActor
    static func currentRoute(for module: ModuleType?) -> LLMRoute {
        route(
            for: module,
            enabled: isEnabled,
            modelAvailable: isModelAvailable,
            languagesSupported: supports(Language.storedNative) && supports(Language.storedTarget)
        )
    }

    /// The provider for `module` right now: Apple's model or the configured one.
    @MainActor
    static func provider(for module: ModuleType?) -> any LLMProvider {
        switch currentRoute(for: module) {
        case .configured:
            return LLMConfiguration().makeProvider()
        case .appleOnDevice:
            #if canImport(FoundationModels)
            if #available(macOS 26.0, *) { return AppleOnDeviceClient() }
            #endif
            return LLMConfiguration().makeProvider()
        }
    }

    /// True when the module would use Apple's model if only the module allowed
    /// it — i.e. it was sent to the configured provider because Apple's model
    /// isn't reliable for it. Used to explain a failure of that provider.
    @MainActor
    static func isFallback(_ module: ModuleType) -> Bool {
        currentRoute(for: nil) == .appleOnDevice && currentRoute(for: module) == .configured
    }

    // MARK: Availability

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static var isModelAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    static func supports(_ language: Language) -> Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let code = language.shortCode.lowercased()
            return SystemLanguageModel.default.supportedLanguages.contains {
                $0.languageCode?.identifier == code
            }
        }
        #endif
        return false
    }

    /// Why the model can't be used right now, or nil when it can. Shown in
    /// Settings next to the toggle.
    static var unavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                let unsupported = [Language.storedNative, Language.storedTarget].filter { !supports($0) }
                guard let first = unsupported.first else { return nil }
                return String(localized: "Apple's on-device model doesn't support \(first.nativeName) yet.")
            case .unavailable(.appleIntelligenceNotEnabled):
                return String(localized: "Turn on Apple Intelligence in System Settings to use it.")
            case .unavailable(.deviceNotEligible):
                return String(localized: "This Mac doesn't support Apple Intelligence.")
            case .unavailable(.modelNotReady):
                return String(localized: "The model is still downloading. Try again later.")
            case .unavailable:
                return String(localized: "Apple's on-device model isn't available right now.")
            }
        }
        #endif
        return String(localized: "Requires macOS 26 or later.")
    }
}

// MARK: - Client

#if canImport(FoundationModels)
@available(macOS 26.0, *)
struct AppleOnDeviceClient: LLMProvider {
    enum ClientError: LocalizedError {
        case generation(String)

        var errorDescription: String? {
            switch self {
            case .generation(let message): return message
            }
        }
    }

    func chat(system: String, user: String, temperature: Double, maxTokens: Int, topP: Double) async throws -> String {
        let session = LanguageModelSession(instructions: system)
        do {
            let response = try await session.respond(to: user, options: options(temperature, maxTokens))
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.map(error)
        }
    }

    @discardableResult
    func stream(
        system: String, user: String, temperature: Double, maxTokens: Int, topP: Double,
        onToken: @MainActor @escaping (String) -> Void
    ) async throws -> LLMFinishReason? {
        let session = LanguageModelSession(instructions: system)
        var emitted = ""
        do {
            // Snapshots are cumulative; hand the caller only what's new so
            // it can keep appending the way it does for SSE deltas.
            for try await snapshot in session.streamResponse(to: user, options: options(temperature, maxTokens)) {
                let text = snapshot.content
                if text.hasPrefix(emitted) {
                    let delta = String(text.dropFirst(emitted.count))
                    if !delta.isEmpty { onToken(delta) }
                    emitted = text
                }
            }
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.map(error)
        }
        return .stop
    }

    private func options(_ temperature: Double, _ maxTokens: Int) -> GenerationOptions {
        GenerationOptions(temperature: temperature, maximumResponseTokens: maxTokens)
    }

    private static func map(_ error: LanguageModelSession.GenerationError) -> ClientError {
        switch error {
        case .guardrailViolation:
            return .generation(String(localized: "Apple's on-device model declined to answer this one."))
        case .unsupportedLanguageOrLocale:
            return .generation(String(localized: "Apple's on-device model doesn't support this language."))
        case .exceededContextWindowSize:
            return .generation(String(localized: "The selection is too long for Apple's on-device model."))
        default:
            return .generation(error.localizedDescription)
        }
    }
}
#endif
