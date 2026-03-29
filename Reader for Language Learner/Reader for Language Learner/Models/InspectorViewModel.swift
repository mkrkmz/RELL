//
//  InspectorViewModel.swift
//  Reader for Language Learner
//

import Foundation

// MARK: - InspectorViewModel

@MainActor
@Observable
final class InspectorViewModel {
    var outputs: [ModuleType: String] = [:]
    var loading: [ModuleType: Bool] = [:]
    var errors: [ModuleType: String] = [:]

    /// Cancellable task handles per module.
    var activeTasks: [ModuleType: Task<Void, Never>] = [:]

    /// LRU output cache — survives word-to-word navigation.
    let cache = LRUCache<OutputCacheKey, [ModuleType: String]>(capacity: 20)

    // MARK: - Reset

    /// Clears display state and cancels in-flight tasks. Does NOT clear the cache.
    func resetAll() {
        cancelAll()
        outputs.removeAll()
        loading.removeAll()
        errors.removeAll()
    }

    // MARK: - Cache helpers

    func snapshotToCache(key: OutputCacheKey) {
        let snapshot = outputs.filter { !$0.value.isEmpty }
        guard !snapshot.isEmpty else { return }
        var merged = cache.get(key) ?? [:]
        for (module, value) in snapshot { merged[module] = value }
        cache.set(key, merged)
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
