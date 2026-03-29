//
//  LRUCache.swift
//  Reader for Language Learner
//
//  Extracted from InspectorViewModel.swift
//

import Foundation

// MARK: - LRU Cache

/// Lightweight LRU cache backed by an ordered dictionary (insertion order = LRU order).
struct LRUCache<Key: Hashable, Value> {
    private let capacity: Int
    private var store: [Key: Value] = [:]
    private var order: [Key] = []   // front = oldest, back = most recent

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    mutating func get(_ key: Key) -> Value? {
        guard let value = store[key] else { return nil }
        touch(key)
        return value
    }

    mutating func set(_ key: Key, _ value: Value) {
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

    mutating func removeAll() {
        store.removeAll()
        order.removeAll()
    }

    private mutating func touch(_ key: Key) {
        if let index = order.firstIndex(of: key) {
            order.remove(at: index)
        }
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
