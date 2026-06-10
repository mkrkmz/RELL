//
//  InspectorViewModel.swift
//  Reader for Language Learner
//

import Foundation
import os

// MARK: - InspectorViewModel

@MainActor
@Observable
final class InspectorViewModel {
    static let cacheCapacity = 50

    var outputs: [ModuleType: String] = [:]
    var loading: [ModuleType: Bool] = [:]
    var errors: [ModuleType: String] = [:]
    /// True if the module's output was likely cut off due to the token limit.
    var wasTruncated: [ModuleType: Bool] = [:]

    /// Cancellable task handles per module.
    var activeTasks: [ModuleType: Task<Void, Never>] = [:]

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
    }

    // MARK: - Cache helpers

    func snapshotToCache(key: OutputCacheKey) {
        let snapshot = outputs.filter { !$0.value.isEmpty }
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
        loading[module] = false
    }

    func cancelAll() {
        for (_, task) in activeTasks { task.cancel() }
        activeTasks.removeAll()
    }
}
