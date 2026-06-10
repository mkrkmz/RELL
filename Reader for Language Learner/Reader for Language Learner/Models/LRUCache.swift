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

    /// All entries from least- to most-recently used. Used to migrate a
    /// decoded snapshot into a cache with the current capacity.
    var entriesOldestFirst: [(key: Key, value: Value)] {
        order.compactMap { key in
            store[key].map { (key, $0) }
        }
    }

    private mutating func touch(_ key: Key) {
        if let index = order.firstIndex(of: key) {
            order.remove(at: index)
        }
        order.append(key)
    }
}

// MARK: - Codable

/// Persists entries in LRU order so a saved cache restores with the same
/// eviction behavior. `capacity` comes from the live cache, not the file,
/// so code changes to the default capacity win over old snapshots.
extension LRUCache: Codable where Key: Codable, Value: Codable {
    private enum CodingKeys: String, CodingKey {
        case keys, values
    }

    init(from decoder: Decoder) throws {
        self.init(capacity: Int.max)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let keys = try container.decode([Key].self, forKey: .keys)
        let values = try container.decode([Value].self, forKey: .values)
        for (key, value) in zip(keys, values) {
            set(key, value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(order, forKey: .keys)
        try container.encode(order.compactMap { store[$0] }, forKey: .values)
    }
}

/// Uniquely identifies a lookup context for cache keying.
/// Includes provider + model + native language so that switching any of them
/// neither hits stale entries nor wipes still-valid ones.
struct OutputCacheKey: Hashable, Codable {
    let term: String
    let mode: String
    let detail: String
    let domain: String
    let provider: String
    let model: String
    var native: String = ""
}

extension OutputCacheKey {
    private enum CodingKeys: String, CodingKey {
        case term, mode, detail, domain, provider, model, native
    }

    // Custom decode: `native` was added after the first persisted snapshots,
    // so it falls back to "" when missing.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        term     = try container.decode(String.self, forKey: .term)
        mode     = try container.decode(String.self, forKey: .mode)
        detail   = try container.decode(String.self, forKey: .detail)
        domain   = try container.decode(String.self, forKey: .domain)
        provider = try container.decode(String.self, forKey: .provider)
        model    = try container.decode(String.self, forKey: .model)
        native   = try container.decodeIfPresent(String.self, forKey: .native) ?? ""
    }
}
