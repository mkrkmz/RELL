//
//  InspectorViewModel.swift
//  Reader for Language Learner
//

import Foundation
import os

// MARK: - InspectorViewModel

/// One question/answer pair in the inspector's Ask AI thread.
struct FollowUpExchange: Identifiable {
    let id: UUID
    let question: String
    var answer: String
    var isLoading: Bool
    var error: String?
}

@MainActor
@Observable
final class InspectorViewModel {
    /// Off the main actor: on macOS 15 a main-actor deinit run outside a
    /// task crashes when it releases another one (v16 S0, CI crash reports).
    nonisolated deinit {}

    static let cacheCapacity = 50

    var outputs: [ModuleType: String] = [:]
    var loading: [ModuleType: Bool] = [:]
    var errors: [ModuleType: String] = [:]
    /// True if the module's output was likely cut off due to the token limit.
    var wasTruncated: [ModuleType: Bool] = [:]

    /// Cancellable task handles per module.
    var activeTasks: [ModuleType: Task<Void, Never>] = [:]

    /// How long each finished module took, shown in the result header.
    var moduleElapsed: [ModuleType: Double] = [:]
    private var moduleStartTimes: [ModuleType: Date] = [:]
    /// The live request per module. A cancelled request finishes after its
    /// replacement has started; it may only touch state while it's current.
    private var currentRunIDs: [ModuleType: UUID] = [:]
    private var currentFollowUpRunID: UUID?

    /// Session-scoped "Ask AI" follow-up exchanges for the current selection.
    var followUps: [FollowUpExchange] = []
    var followUpTask: Task<Void, Never>?

    var isAskingFollowUp: Bool {
        followUps.last?.isLoading == true
    }

    /// Caps concurrent requests to local LLM servers (LM Studio / Ollama),
    /// which serialize on a single GPU context anyway.
    let localRequestGate = AsyncLimiter(limit: 2)

    /// LRU output cache — survives word-to-word navigation and, via the disk
    /// snapshot in Application Support, app restarts.
    var cache: LRUCache<OutputCacheKey, [ModuleType: String]>

    private let cacheFileURL: URL?

    init(cacheFileURL customCacheFileURL: URL? = nil) {
        let url = customCacheFileURL
            ?? FileManager.default.rellAppSupportDirectory()?.appendingPathComponent("llm_output_cache.json")
        self.cacheFileURL = url
        self.cache = Self.loadCache(from: url)
    }

    /// Session-scoped history of the last 20 looked-up terms (most recent first).
    private(set) var recentTerms: [String] = []

    func addToRecents(_ term: String) {
        recentTerms.removeAll { $0.lowercased() == term.lowercased() }
        recentTerms.insert(term, at: 0)
        if recentTerms.count > 20 { recentTerms.removeLast() }
    }

    // MARK: - Reset

    /// Clears display state and cancels in-flight tasks. Does NOT clear the cache.
    func resetAll() {
        cancelAll()
        outputs.removeAll()
        loading.removeAll()
        errors.removeAll()
        wasTruncated.removeAll()
        followUpTask?.cancel()
        followUpTask = nil
        followUps.removeAll()
    }

    // MARK: - Cache helpers

    /// Caches the finished modules. A module that ended in an error is left
    /// out: its partial text would otherwise come back as a "cache hit" for
    /// this word from then on, on every launch.
    func snapshotToCache(key: OutputCacheKey) {
        let snapshot = outputs.filter { !$0.value.isEmpty && errors[$0.key] == nil }
        guard !snapshot.isEmpty else { return }
        var merged = cache.get(key) ?? [:]
        for (module, value) in snapshot { merged[module] = value }
        cache.set(key, merged)
        persistCache()
    }

    /// Clears the in-memory cache and its disk snapshot.
    func clearCache() {
        cache.removeAll()
        persistCache()
    }

    // MARK: - Cache persistence

    private static func loadCache(from url: URL?) -> LRUCache<OutputCacheKey, [ModuleType: String]> {
        var fresh = LRUCache<OutputCacheKey, [ModuleType: String]>(capacity: cacheCapacity)
        guard let url else { return fresh }
        let restored = RELLJSONStore.load(
            LRUCache<OutputCacheKey, [ModuleType: String]>.self,
            from: url,
            storeName: "InspectorOutputCache",
            userVisible: false,
            defaultValue: LRUCache(capacity: cacheCapacity)
        )
        // Re-insert into a cache with the current capacity; oldest entries
        // beyond the limit fall off naturally.
        for (key, value) in restored.entriesOldestFirst {
            fresh.set(key, value)
        }
        return fresh
    }

    private func persistCache() {
        guard let cacheFileURL else { return }
        do {
            try RELLJSONStore.save(cache, to: cacheFileURL, storeName: "InspectorOutputCache")
        } catch {
            AppLogger.persistence.error("LLM output cache save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @discardableResult
    func loadFromCache(key: OutputCacheKey) -> Bool {
        guard let cached = cache.get(key), !cached.isEmpty else { return false }
        for (module, value) in cached {
            outputs[module] = value
        }
        return true
    }

    // MARK: - Cancellation

    func cancel(module: ModuleType) {
        activeTasks[module]?.cancel()
        activeTasks[module] = nil
        currentRunIDs[module] = nil
        loading[module] = false
        moduleElapsed[module] = nil
    }

    func cancelAll() {
        for (_, task) in activeTasks { task.cancel() }
        activeTasks.removeAll()
        currentRunIDs.removeAll()
    }

    // MARK: - Running a module

    /// Everything one module request needs, resolved by the view (prompts,
    /// route, budgets) so the running itself can be tested without a view.
    struct ModuleRun {
        let module: ModuleType
        let system: String
        let user: String
        let temperature: Double
        let maxTokens: Int
        let cacheKey: OutputCacheKey
        /// Sent to the configured provider only because Apple's model isn't
        /// reliable for this module — said so if that provider fails.
        let isFallback: Bool
        /// LM Studio / Ollama: share `localRequestGate`.
        let usesLocalGate: Bool
    }

    /// Streams `run.module` from `provider` into `outputs`, then records the
    /// error, the truncation guess, the elapsed time and the cache snapshot.
    /// Replaces any request already running for that module.
    func start(_ run: ModuleRun, provider: any LLMProvider) {
        let module = run.module
        cancel(module: module)
        moduleStartTimes[module] = Date()
        loading[module] = true
        errors[module] = nil
        wasTruncated[module] = nil
        outputs[module] = ""

        let runID = UUID()
        currentRunIDs[module] = runID
        let gate = localRequestGate
        let task = Task { [weak self] in
            var finishReason: LLMFinishReason?
            var failure: Error?
            do {
                if run.usesLocalGate { await gate.acquire() }
                defer { if run.usesLocalGate { gate.release() } }
                try Task.checkCancellation()
                finishReason = try await provider.stream(
                    system: run.system,
                    user: run.user,
                    temperature: run.temperature,
                    maxTokens: run.maxTokens,
                    topP: 0.9
                ) { token in
                    guard let self, self.currentRunIDs[module] == runID else { return }
                    self.outputs[module, default: ""] += token
                }
            } catch {
                failure = error
            }
            guard let self, self.currentRunIDs[module] == runID else { return }
            self.finish(run, finishReason: finishReason, failure: failure, cancelled: Task.isCancelled)
        }
        activeTasks[module] = task
    }

    private func finish(_ run: ModuleRun, finishReason: LLMFinishReason?, failure: Error?, cancelled: Bool) {
        let module = run.module
        if !cancelled {
            if let failure {
                let message = LLMErrorMessage.userMessage(for: failure)
                // Say why this module needed the server at all.
                errors[module] = run.isFallback
                    ? String(localized: "Apple's on-device model isn't reliable for this module, so it uses your AI provider — which failed: \(message)")
                    : message
            }
            wasTruncated[module] = Self.looksTruncated(
                finishReason: finishReason,
                outputLength: outputs[module]?.count ?? 0,
                maxTokens: run.maxTokens
            )
            snapshotToCache(key: run.cacheKey)
            if let start = moduleStartTimes[module] {
                moduleElapsed[module] = Date().timeIntervalSince(start)
            }
        }
        loading[module] = false
        activeTasks[module] = nil
        currentRunIDs[module] = nil
    }

    /// The server's finish reason when it gave one; otherwise a heuristic —
    /// about 3.5 characters per token, and output at 90% of the budget most
    /// likely hit the limit.
    nonisolated static func looksTruncated(finishReason: LLMFinishReason?, outputLength: Int, maxTokens: Int) -> Bool {
        if let finishReason { return finishReason == .length }
        let budgetChars = Int(Double(maxTokens) * 3.5)
        return outputLength >= Int(Double(budgetChars) * 0.90)
    }

    // MARK: - Ask AI

    /// Appends a follow-up exchange and streams its answer into it.
    func startFollowUp(
        question: String,
        system: String,
        provider: any LLMProvider,
        usesLocalGate: Bool
    ) {
        followUpTask?.cancel()
        let exchangeID = UUID()
        followUps.append(
            FollowUpExchange(id: exchangeID, question: question, answer: "", isLoading: true, error: nil)
        )
        let runID = UUID()
        currentFollowUpRunID = runID
        let gate = localRequestGate
        followUpTask = Task { [weak self] in
            var failure: Error?
            do {
                if usesLocalGate { await gate.acquire() }
                defer { if usesLocalGate { gate.release() } }
                try Task.checkCancellation()
                _ = try await provider.stream(
                    system: system, user: question, temperature: 0.3, maxTokens: 400, topP: 0.9
                ) { token in
                    guard let self, self.currentFollowUpRunID == runID,
                          let index = self.followUpIndex(exchangeID) else { return }
                    self.followUps[index].answer += token
                }
            } catch {
                failure = error
            }
            guard let self else { return }
            if let index = self.followUpIndex(exchangeID) {
                if let failure, !Task.isCancelled {
                    self.followUps[index].error = LLMErrorMessage.userMessage(for: failure)
                }
                self.followUps[index].isLoading = false
            }
            if self.currentFollowUpRunID == runID {
                self.followUpTask = nil
                self.currentFollowUpRunID = nil
            }
        }
    }

    private func followUpIndex(_ id: UUID) -> Int? {
        followUps.firstIndex { $0.id == id }
    }
}
