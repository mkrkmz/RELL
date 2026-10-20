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

    /// How long each finished module took.
    var moduleElapsed: [ModuleType: Double] = [:]

    /// Where a module's answer came from (v17 S2): a request in
    /// `LLMRequestLog`, or the saved answers. The result's footer reads it.
    enum AnswerSource: Equatable {
        case request(UUID)
        case cached
    }
    private(set) var answerSources: [ModuleType: AnswerSource] = [:]
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
        answerSources.removeAll()
        clearCustom()
        followUpTask?.cancel()
        followUpTask = nil
        followUps.removeAll()
    }

    // MARK: - Cache helpers

    /// Caches the finished modules. A module that ended in an error is left
    /// out: its partial text would otherwise come back as a "cache hit" for
    /// this word from then on, on every launch.
    ///
    /// v19 S0: a module that reads the sentence is kept under the key with
    /// the sentence; the others under the key without it, so the word's
    /// examples or etymology still come from the cache in another sentence.
    func snapshotToCache(key: OutputCacheKey) {
        let snapshot = outputs.filter { !$0.value.isEmpty && errors[$0.key] == nil }
        guard !snapshot.isEmpty else { return }
        var byKey: [OutputCacheKey: [ModuleType: String]] = [:]
        for (module, value) in snapshot {
            byKey[Self.storageKey(for: module, in: key), default: [:]][module] = value
        }
        for (storeKey, values) in byKey {
            var merged = cache.get(storeKey) ?? [:]
            for (module, value) in values { merged[module] = value }
            cache.set(storeKey, merged)
        }
        persistCache()
    }

    /// Where `module`'s answer for `key` is kept.
    static func storageKey(for module: ModuleType, in key: OutputCacheKey) -> OutputCacheKey {
        let mode = ExplainMode(rawValue: key.mode) ?? .word
        return module.usesContext(mode: mode) && !key.context.isEmpty ? key : key.withoutContext
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
    /// Which module a word with saved answers opens on: the open one if it
    /// has an answer, else the one used last, else the first in the grid's
    /// order that has one (v17 S2 live pass: a word looked up before opened
    /// blank until you clicked its module).
    static func moduleToShow(
        active: ModuleType?, lastUsed: ModuleType, primary: [ModuleType],
        outputs: [ModuleType: String], isEnabled: (ModuleType) -> Bool
    ) -> ModuleType? {
        func hasAnswer(_ module: ModuleType) -> Bool { !(outputs[module] ?? "").isEmpty }
        if let active, hasAnswer(active) { return active }
        return ([lastUsed] + primary + ModuleType.allCases).first { isEnabled($0) && hasAnswer($0) } ?? active
    }

    func loadFromCache(key: OutputCacheKey) -> Bool {
        var found: [ModuleType: String] = [:]
        // Each module from the key it's kept under (`storageKey`).
        for storeKey in Set([key, key.withoutContext]) {
            for (module, value) in cache.get(storeKey) ?? [:] where Self.storageKey(for: module, in: key) == storeKey {
                found[module] = value
            }
        }
        guard !found.isEmpty else { return false }
        for (module, value) in found {
            outputs[module] = value
            answerSources[module] = .cached
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
        for (_, task) in customTasks { task.cancel() }
        customTasks.removeAll()
        customRunIDs.removeAll()
    }

    // MARK: - The reader's own modules (v18 S3)
    //
    // Kept apart from the built-in modules' state: those are keyed by
    // `ModuleType` all through saving, the disk cache and Anki, and own
    // modules stay out of all that.

    private(set) var customOutputs: [UUID: String] = [:]
    private(set) var customLoading: [UUID: Bool] = [:]
    private(set) var customErrors: [UUID: String] = [:]
    private(set) var customSources: [UUID: AnswerSource] = [:]
    @ObservationIgnored private var customTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var customRunIDs: [UUID: UUID] = [:]
    /// In memory; the key holds the prompt's tag, so an edited prompt
    /// never shows an old answer.
    @ObservationIgnored private var customCache = LRUCache<String, String>(capacity: 60)

    func loadCustomFromCache(_ id: UUID, key: String) -> Bool {
        guard let cached = customCache.get(key), !cached.isEmpty else { return false }
        customOutputs[id] = cached
        customErrors[id] = nil
        customSources[id] = .cached
        return true
    }

    func startCustom(_ id: UUID, system: String, user: String, maxTokens: Int, cacheKey: String, provider: any LLMProvider) {
        cancelCustom(id)
        customOutputs[id] = ""
        customErrors[id] = nil
        customLoading[id] = true
        customSources[id] = (provider as? RecordedLLMProvider).map { .request($0.id) }
        let runID = UUID()
        customRunIDs[id] = runID
        customTasks[id] = Task { [weak self] in
            var failure: Error?
            do {
                _ = try await provider.stream(system: system, user: user, temperature: 0.4,
                                              maxTokens: maxTokens, topP: 0.9) { token in
                    guard let self, self.customRunIDs[id] == runID else { return }
                    self.customOutputs[id, default: ""] += token
                }
            } catch {
                failure = error
            }
            (provider as? RecordedLLMProvider)?.dropIfNotSent()
            guard let self, self.customRunIDs[id] == runID else { return }
            if let failure, !Task.isCancelled {
                self.customErrors[id] = LLMErrorMessage.userMessage(for: failure)
            } else if let output = self.customOutputs[id], !output.isEmpty, !Task.isCancelled {
                self.customCache.set(cacheKey, output)
            }
            self.customLoading[id] = false
            self.customTasks[id] = nil
            self.customRunIDs[id] = nil
        }
    }

    func cancelCustom(_ id: UUID) {
        customTasks[id]?.cancel()
        customTasks[id] = nil
        customRunIDs[id] = nil
        customLoading[id] = false
    }

    private func clearCustom() {
        customOutputs.removeAll()
        customLoading.removeAll()
        customErrors.removeAll()
        customSources.removeAll()
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
    }

    /// Streams `run.module` from `provider` into `outputs`, then records the
    /// error, the truncation guess, the elapsed time and the cache snapshot.
    /// Replaces any request already running for that module.
    func start(_ run: ModuleRun, provider: any LLMProvider) {
        let module = run.module
        cancel(module: module)
        moduleStartTimes[module] = Date()
        answerSources[module] = (provider as? RecordedLLMProvider).map { .request($0.id) }
        loading[module] = true
        errors[module] = nil
        wasTruncated[module] = nil
        outputs[module] = ""

        let runID = UUID()
        currentRunIDs[module] = runID
        // A model on this Mac waits its turn inside the provider
        // (`LLMScheduler`, v17 S1); cancelling this task takes it out of
        // the queue.
        let task = Task { [weak self] in
            var finishReason: LLMFinishReason?
            var failure: Error?
            do {
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
            (provider as? RecordedLLMProvider)?.dropIfNotSent()
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
            // v19 S5: the answer arrived where the focus isn't — say so.
            Announcement.post(failure == nil
                ? String(localized: "\(module.title) ready")
                : String(localized: "\(module.title) failed"))
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
        provider: any LLMProvider
    ) {
        followUpTask?.cancel()
        let exchangeID = UUID()
        followUps.append(
            FollowUpExchange(id: exchangeID, question: question, answer: "", isLoading: true, error: nil)
        )
        let runID = UUID()
        currentFollowUpRunID = runID
        followUpTask = Task { [weak self] in
            var failure: Error?
            do {
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
            (provider as? RecordedLLMProvider)?.dropIfNotSent()
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
