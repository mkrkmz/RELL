//
//  LRUCache.swift
//  Reader for Language Learner
//
//  Extracted from InspectorViewModel.swift
//

import Foundation

// MARK: - LRU Cache

/// Lightweight LRU cache backed by an ordered dictionary (insertion order = LRU order).
final class LRUCache<Key: Hashable, Value> {
    private let capacity: Int
    private var store: [Key: Value] = [:]
    private var order: [Key] = []   // front = oldest, back = most recent

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    func get(_ key: Key) -> Value? {
        guard let value = store[key] else { return nil }
        touch(key)
        return value
    }

    func set(_ key: Key, _ value: Value) {
        if store[key] != nil {
            touch(key)
        } else {
            if store.count >= capacity, let evict = order.first {
                store.removeValue(forKey: evict)
                order.removeFirst()
            }
            order.append(key)
        }
        store[key] = value
    }

    func removeAll() {
        store.removeAll()
        order.removeAll()
    }

    private func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}

/// Uniquely identifies a lookup context for cache keying.
struct OutputCacheKey: Hashable {
    let term: String
    let mode: String
    let detail: String
    let domain: String
}
