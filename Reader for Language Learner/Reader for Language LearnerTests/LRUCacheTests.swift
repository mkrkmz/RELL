//
//  LRUCacheTests.swift
//  Reader for Language LearnerTests
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class LRUCacheTests: XCTestCase {

    func testGetReturnsNilForMissingKey() {
        var cache = LRUCache<String, Int>(capacity: 3)
        XCTAssertNil(cache.get("missing"))
    }

    func testSetAndGet() {
        var cache = LRUCache<String, Int>(capacity: 3)
        cache.set("a", 1)
        cache.set("b", 2)
        XCTAssertEqual(cache.get("a"), 1)
        XCTAssertEqual(cache.get("b"), 2)
    }

    func testEvictsOldestWhenFull() {
        var cache = LRUCache<String, Int>(capacity: 2)
        cache.set("a", 1)
        cache.set("b", 2)
        cache.set("c", 3) // should evict "a"
        XCTAssertNil(cache.get("a"), "Oldest entry should be evicted")
        XCTAssertEqual(cache.get("b"), 2)
        XCTAssertEqual(cache.get("c"), 3)
    }

    func testGetTouchesEntry() {
        var cache = LRUCache<String, Int>(capacity: 2)
        cache.set("a", 1)
        cache.set("b", 2)
        _ = cache.get("a") // touch "a", making "b" the oldest
        cache.set("c", 3)  // should evict "b" (oldest)
        XCTAssertEqual(cache.get("a"), 1, "Touched entry should survive")
        XCTAssertNil(cache.get("b"), "Untouched oldest should be evicted")
        XCTAssertEqual(cache.get("c"), 3)
    }

    func testOverwriteExistingKey() {
        var cache = LRUCache<String, Int>(capacity: 2)
        cache.set("a", 1)
        cache.set("a", 99)
        XCTAssertEqual(cache.get("a"), 99)
    }

    func testRemoveAll() {
        var cache = LRUCache<String, Int>(capacity: 5)
        cache.set("a", 1)
        cache.set("b", 2)
        cache.removeAll()
        XCTAssertNil(cache.get("a"))
        XCTAssertNil(cache.get("b"))
    }

    func testCapacityOfOne() {
        var cache = LRUCache<String, Int>(capacity: 1)
        cache.set("a", 1)
        cache.set("b", 2)
        XCTAssertNil(cache.get("a"))
        XCTAssertEqual(cache.get("b"), 2)
    }

    func testCapacityClampedToMinimumOne() {
        var cache = LRUCache<String, Int>(capacity: 0)
        cache.set("a", 1)
        XCTAssertEqual(cache.get("a"), 1, "Capacity should be clamped to 1")
    }
}
