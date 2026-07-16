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

    // MARK: - Codable

    func testCodableRoundTripPreservesEntriesAndOrder() throws {
        var cache = LRUCache<String, Int>(capacity: 5)
        cache.set("a", 1)
        cache.set("b", 2)
        cache.set("c", 3)
        _ = cache.get("a") // "b" is now the oldest

        let data = try JSONEncoder().encode(cache)
        var decoded = try JSONDecoder().decode(LRUCache<String, Int>.self, from: data)

        XCTAssertEqual(
            decoded.entriesOldestFirst.map(\.key), ["b", "c", "a"],
            "Decoded cache should preserve LRU order (b was oldest after touching a)"
        )
        XCTAssertEqual(decoded.get("a"), 1)
        XCTAssertEqual(decoded.get("b"), 2)
        XCTAssertEqual(decoded.get("c"), 3)
    }

    func testEntriesOldestFirstReflectsUsage() {
        var cache = LRUCache<String, Int>(capacity: 3)
        cache.set("a", 1)
        cache.set("b", 2)
        _ = cache.get("a")

        XCTAssertEqual(cache.entriesOldestFirst.map(\.key), ["b", "a"])
    }

    func testDecodedSnapshotMigratesIntoSmallerCapacity() throws {
        var big = LRUCache<String, Int>(capacity: 10)
        for (index, key) in ["a", "b", "c", "d"].enumerated() {
            big.set(key, index)
        }
        let data = try JSONEncoder().encode(big)
        let restored = try JSONDecoder().decode(LRUCache<String, Int>.self, from: data)

        var small = LRUCache<String, Int>(capacity: 2)
        for (key, value) in restored.entriesOldestFirst {
            small.set(key, value)
        }

        XCTAssertNil(small.get("a"), "Oldest entries should fall off when migrating to a smaller capacity")
        XCTAssertNil(small.get("b"))
        XCTAssertEqual(small.get("c"), 2)
        XCTAssertEqual(small.get("d"), 3)
    }

    // MARK: - OutputCacheKey

    func testOutputCacheKeyDistinguishesNativeLanguage() {
        let turkish = OutputCacheKey(
            term: "orbit", mode: "Word", detail: "Short", domain: "General",
            provider: "LM Studio", model: "m", native: "Turkish"
        )
        let german = OutputCacheKey(
            term: "orbit", mode: "Word", detail: "Short", domain: "General",
            provider: "LM Studio", model: "m", native: "German"
        )
        XCTAssertNotEqual(turkish, german)
    }

    func testOutputCacheKeyCodableRoundTrip() throws {
        let key = OutputCacheKey(
            term: "orbit", mode: "Word", detail: "Short", domain: "General",
            provider: "LM Studio", model: "m", native: "Turkish"
        )
        let data = try JSONEncoder().encode(key)
        let decoded = try JSONDecoder().decode(OutputCacheKey.self, from: data)
        XCTAssertEqual(decoded, key)
    }

    func testOutputCacheKeyDecodesLegacyPayloadWithoutNative() throws {
        let legacyJSON = """
        {"term":"orbit","mode":"Word","detail":"Short","domain":"General","provider":"LM Studio","model":"m"}
        """
        let decoded = try JSONDecoder().decode(OutputCacheKey.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(decoded.native, "")
        XCTAssertEqual(decoded.target, "")
    }

    func testOutputCacheKeyDistinguishesTargetLanguage() {
        let english = OutputCacheKey(
            term: "orbit", mode: "Word", detail: "Short", domain: "General",
            provider: "LM Studio", model: "m", native: "Turkish", target: "English"
        )
        let german = OutputCacheKey(
            term: "orbit", mode: "Word", detail: "Short", domain: "General",
            provider: "LM Studio", model: "m", native: "Turkish", target: "German"
        )
        XCTAssertNotEqual(english, german)
    }

    func testOutputCacheKeyDecodesV122PayloadWithoutTarget() throws {
        let json = """
        {"term":"orbit","mode":"Word","detail":"Short","domain":"General","provider":"LM Studio","model":"m","native":"Turkish"}
        """
        let decoded = try JSONDecoder().decode(OutputCacheKey.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.native, "Turkish")
        XCTAssertEqual(decoded.target, "")
    }
}
