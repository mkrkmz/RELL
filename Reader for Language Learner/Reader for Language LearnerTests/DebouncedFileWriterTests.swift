//
//  DebouncedFileWriterTests.swift
//  Reader for Language LearnerTests
//
//  Covers the off-main debounced persistence primitive (Roadmap v9 Sprint 1):
//  write-through mode, coalescing a burst to the latest value, synchronous
//  flush, and the termination-time coordinator flush.
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class DebouncedFileWriterTests: XCTestCase {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    }

    private func encoding(_ values: [Int]) -> () throws -> Data {
        { try JSONEncoder().encode(values) }
    }

    private func decodeInts(_ url: URL) throws -> [Int] {
        try JSONDecoder().decode([Int].self, from: Data(contentsOf: url))
    }

    func testWriteThroughPersistsSynchronously() throws {
        let url = tempURL()
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        let writer = DebouncedFileWriter(fileURL: url, storeName: "wt", debounce: 0)
        writer.schedule(encoding([1, 2, 3]))

        XCTAssertEqual(try decodeInts(url), [1, 2, 3], "debounce 0 must write inline")
    }

    func testWriteThroughReportsSuccessThroughOnResult() throws {
        let url = tempURL()
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        var results: [String?] = []
        let writer = DebouncedFileWriter(fileURL: url, storeName: "res", debounce: 0)
        writer.onResult = { results.append($0) }
        writer.schedule(encoding([7]))

        XCTAssertEqual(results, [String?.none], "nil result signals a successful write")
    }

    func testFlushWritesPendingImmediatelyWithoutWaitingOutTheDebounce() throws {
        let url = tempURL()
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        // A long debounce that we never wait out — flush must force it now.
        let writer = DebouncedFileWriter(fileURL: url, storeName: "flush", debounce: 5)
        writer.schedule(encoding([9]))
        writer.flush()

        XCTAssertEqual(try decodeInts(url), [9])
    }

    func testBurstCoalescesToTheLatestValue() async throws {
        let url = tempURL()
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        let writer = DebouncedFileWriter(fileURL: url, storeName: "burst", debounce: 0.15)
        writer.schedule(encoding([1]))
        writer.schedule(encoding([2]))
        writer.schedule(encoding([3]))

        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertEqual(try decodeInts(url), [3], "only the final value in a burst reaches disk")
    }

    func testDebouncedWriteEventuallyLands() async throws {
        let url = tempURL()
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        let writer = DebouncedFileWriter(fileURL: url, storeName: "eventual", debounce: 0.1)
        writer.schedule(encoding([42]))

        try await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertEqual(try decodeInts(url), [42])
    }

    func testCoordinatorFlushAllForcesPendingWrite() throws {
        let url = tempURL()
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        let writer = DebouncedFileWriter(fileURL: url, storeName: "coord", debounce: 5)
        writer.schedule(encoding([100]))
        // Simulates applicationWillTerminate.
        PersistenceCoordinator.flushAll()

        XCTAssertEqual(try decodeInts(url), [100])
        _ = writer  // keep alive through the flush
    }

    func testFlushWithNothingPendingIsANoOp() throws {
        let url = tempURL()
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        let writer = DebouncedFileWriter(fileURL: url, storeName: "noop", debounce: 5)
        writer.flush()   // never scheduled anything

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
