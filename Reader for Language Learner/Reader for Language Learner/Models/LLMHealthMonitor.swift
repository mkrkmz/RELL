//
//  LLMHealthMonitor.swift
//  Reader for Language Learner
//
//  Lightweight reachability probe for the configured LLM backend, so the
//  toolbar can show server status before the first real request fails.
//

import Foundation
import Observation

@MainActor
@Observable
final class LLMHealthMonitor {
    enum Status: Equatable {
        case unknown
        case checking
        case healthy
        case unreachable(String)
    }

    private(set) var status: Status = .unknown
    private(set) var lastLatencyMs: Int?
    private(set) var lastCheckedAt: Date?

    private var checkTask: Task<Void, Never>?

    /// Debounced entry point for settings-change and app-launch triggers.
    func scheduleCheck() {
        checkTask?.cancel()
        checkTask = Task { await check() }
    }

    func check() async {
        let config = LLMConfiguration()
        status = .checking

        guard let url = Self.healthURL(for: config) else {
            status = .unreachable("Invalid server URL — check Settings.")
            lastLatencyMs = nil
            lastCheckedAt = Date()
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        if config.providerType == .openAI, !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }

        let started = ContinuousClock.now
        do {
            // Any HTTP response (including 401/404) proves the server is up;
            // reachability is the only question this probe answers.
            _ = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled else { return }
            lastLatencyMs = Int(started.duration(to: .now) / .milliseconds(1))
            status = .healthy
        } catch {
            guard !Task.isCancelled else { return }
            lastLatencyMs = nil
            status = .unreachable(LLMErrorMessage.userMessage(for: error))
        }
        lastCheckedAt = Date()
    }

    private static func healthURL(for config: LLMConfiguration) -> URL? {
        guard let base = URL(string: config.serverURL) else { return nil }
        switch config.providerType {
        case .lmStudio, .openAI:
            return base.appendingPathComponent("v1/models")
        case .ollama:
            return base.appendingPathComponent("api/tags")
        case .anthropic:
            // No cheap unauthenticated endpoint — a GET on the API root
            // answers fast and confirms the host is reachable.
            return base
        }
    }
}
