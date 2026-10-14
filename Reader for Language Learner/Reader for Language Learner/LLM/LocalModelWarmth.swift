//
//  LocalModelWarmth.swift
//  Reader for Language Learner
//
//  Keeps a model on this Mac loaded (Roadmap v17 Sprint 1). Local servers
//  unload a model left idle — Ollama after 5 minutes, LM Studio after 60 —
//  and the next request waits for it to load again: in S0 the first word
//  took 12.4 s against 0.7 s once loaded. When a book opens the model is
//  loaded in the background, before the first word you look up; Ollama is
//  then asked to keep it for half an hour after each request (its OpenAI
//  route has no `keep_alive`, so this goes through its own API and generates
//  nothing). Cloud models and Apple's model are left alone.
//

import Foundation

@MainActor
enum LocalModelWarmth {
    /// How long Ollama keeps the model after a request.
    nonisolated static let keepAlive = "30m"
    /// At most one ping per model in this time.
    nonisolated static let minimumInterval: TimeInterval = 60

    private static var lastPing: [String: Date] = [:]

    /// A book opened: load the model now.
    static func documentOpened(configuration: LLMConfiguration = LLMConfiguration(), now: Date = Date()) {
        guard !RELLProcess.isTestHost else { return }
        AppleOnDevice.prewarm()
        warm(configuration, now: now)
    }

    /// A request to a model on this Mac finished: Ollama keeps it longer.
    static func requestFinished(configuration: LLMConfiguration = LLMConfiguration(), now: Date = Date()) {
        guard !RELLProcess.isTestHost, configuration.providerType == .ollama else { return }
        warm(configuration, now: now)
    }

    private static func warm(_ configuration: LLMConfiguration, now: Date) {
        guard configuration.runsOnThisMac else { return }
        let key = [configuration.providerType.rawValue, configuration.serverURL, configuration.model].joined(separator: "|")
        guard shouldPing(last: lastPing[key], now: now) else { return }
        lastPing[key] = now

        switch configuration.providerType {
        case .ollama:
            guard let request = ollamaKeepAlive(serverURL: configuration.serverURL, model: configuration.model) else { return }
            let log = LLMRequestLog.shared
            let id = log.begin(origin: .prewarm, detail: nil, engine: configuration.providerType.rawValue,
                               model: configuration.model, onThisMac: true)
            Task {
                log.started(id)
                do {
                    let (_, response) = try await LLMSessionPool.session(timeout: 120).data(for: request)
                    let ok = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
                    log.finish(id, ok ? .finished : .failed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"))
                } catch {
                    log.finish(id, RecordedLLMProvider.outcome(for: error))
                }
            }
        case .lmStudio:
            // One token through the queue, behind anything you ask for: LM
            // Studio loads the model to answer it.
            let provider = LLMRequestLog.shared.recording(
                configuration.makeProvider(), origin: .prewarm, route: .configured
            )
            Task {
                _ = try? await provider.chat(system: "", user: "Hi", temperature: 0, maxTokens: 1, topP: 1)
            }
        case .openAI, .anthropic:
            return
        }
    }

    // MARK: Pure

    nonisolated static func shouldPing(last: Date?, now: Date) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= minimumInterval
    }

    /// Ollama's own API: with no prompt it only loads the model and sets
    /// how long it stays.
    nonisolated static func ollamaKeepAlive(serverURL: String, model: String) -> URLRequest? {
        // Same base the chat requests use (`<server>/v1/chat/completions`).
        guard let url = URL(string: "\(serverURL)/api/generate") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(
            withJSONObject: ["model": model, "keep_alive": keepAlive], options: [.sortedKeys]
        )
        return request
    }
}
