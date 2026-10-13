//
//  LLMRequestLogTests.swift
//  Reader for Language LearnerTests
//
//  v17 Sprint 0 — every AI request timed: waiting for its turn, the first
//  word, the whole answer, and how it ended.
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class LLMRequestLogTests: XCTestCase {

    /// A clock the test moves by hand.
    private final class ManualClock {
        var now = Date(timeIntervalSinceReferenceDate: 1_000)
        func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    }

    private struct FakeProvider: LLMProvider {
        var tokens = ["Hel", "lo"]
        var failure: Error?
        var onStart: () -> Void = {}
        var betweenTokens: () -> Void = {}

        func chat(system: String, user: String, temperature: Double, maxTokens: Int, topP: Double) async throws -> String {
            onStart()
            if let failure { throw failure }
            return tokens.joined()
        }

        func stream(
            system: String, user: String, temperature: Double, maxTokens: Int, topP: Double,
            onToken: @MainActor @escaping (String) -> Void
        ) async throws -> LLMFinishReason? {
            onStart()
            if let failure { throw failure }
            for (index, token) in tokens.enumerated() {
                if index > 0 { betweenTokens() }
                onToken(token)
            }
            return .stop
        }
    }

    func testAStreamedRequestIsTimedFromBeingAskedFor() async throws {
        let clock = ManualClock()
        let log = LLMRequestLog(clock: { clock.now })
        let id = log.begin(origin: .module, detail: ModuleType.definitionEN.rawValue, engine: "LM Studio", model: "m")
        clock.advance(2)                       // waits for its turn
        let base = FakeProvider(onStart: { clock.advance(1.5) }, betweenTokens: { clock.advance(1) })
        let provider = RecordedLLMProvider(base: base, id: id, log: log)
        var received = ""
        _ = try await provider.stream(system: "", user: "", temperature: 0, maxTokens: 10, topP: 1) { received += $0 }

        let record = try XCTUnwrap(log.records.first)
        XCTAssertEqual(received, "Hello")
        XCTAssertEqual(try XCTUnwrap(record.wait), 2, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(record.firstToken), 1.5, accuracy: 0.001, "first word, not the last")
        XCTAssertEqual(try XCTUnwrap(record.total), 4.5, accuracy: 0.001)
        XCTAssertEqual(record.outcome, .finished)
        XCTAssertEqual(record.detail, "definitionEN")
    }

    func testFailuresAndCancellationsAreTold() async {
        let log = LLMRequestLog()
        let failing = RecordedLLMProvider(base: FakeProvider(failure: URLError(.timedOut)),
                                          id: log.begin(origin: .warmUp, detail: nil, engine: "Ollama", model: nil), log: log)
        _ = try? await failing.chat(system: "", user: "", temperature: 0, maxTokens: 1, topP: 1)
        let cancelled = RecordedLLMProvider(base: FakeProvider(failure: CancellationError()),
                                            id: log.begin(origin: .module, detail: nil, engine: "Ollama", model: nil), log: log)
        _ = try? await cancelled.chat(system: "", user: "", temperature: 0, maxTokens: 1, topP: 1)

        XCTAssertEqual(log.records.map(\.outcome), [.failed("URLError -1001"), .cancelled], "timed out")
    }

    func testARequestDroppedWhileWaitingIsNeverSent() {
        let log = LLMRequestLog()
        let dropped = RecordedLLMProvider(base: FakeProvider(), id: log.begin(origin: .module, detail: nil, engine: "x", model: nil), log: log)
        dropped.dropIfNotSent()
        XCTAssertEqual(log.neverSent.map(\.id), [dropped.id])
        XCTAssertEqual(log.records.first?.outcome, .cancelled)
    }

    func testDroppingAfterItWentOutChangesNothing() async throws {
        let log = LLMRequestLog()
        let provider = RecordedLLMProvider(base: FakeProvider(), id: log.begin(origin: .module, detail: nil, engine: "x", model: nil), log: log)
        _ = try await provider.chat(system: "", user: "", temperature: 0, maxTokens: 1, topP: 1)
        provider.dropIfNotSent()
        XCTAssertEqual(log.records.first?.outcome, .finished)
        XCTAssertTrue(log.neverSent.isEmpty)
    }

    func testItKeepsTheLatestRequestsOnly() {
        let log = LLMRequestLog()
        let ids = (0..<(LLMRequestLog.capacity + 5)).map { _ in
            log.begin(origin: .gloss, detail: nil, engine: "x", model: nil)
        }
        XCTAssertEqual(log.records.count, LLMRequestLog.capacity)
        XCTAssertEqual(log.records.first?.id, ids[5])
        XCTAssertEqual(log.records.last?.id, ids.last)
    }

    func testTheEngineFollowsTheRoute() {
        let log = LLMRequestLog()
        _ = log.recording(FakeProvider(), origin: .cefr, route: .appleOnDevice)
        _ = log.recording(FakeProvider(), origin: .cefr, route: .configured)
        XCTAssertEqual(log.records[0].engine, AppleOnDevice.providerLabel)
        XCTAssertNil(log.records[0].model)
        XCTAssertEqual(log.records[1].engine, LLMConfiguration().providerType.rawValue)
        XCTAssertEqual(log.records[1].model, LLMConfiguration().model)
    }

    func testBackgroundWorkIsToldApartFromWhatYouWaitFor() {
        XCTAssertTrue(LLMRequestOrigin.module.isForeground)
        XCTAssertTrue(LLMRequestOrigin.quickLookup.isForeground)
        for origin in [LLMRequestOrigin.warmUp, .recap, .gloss, .fill, .cefr] {
            XCTAssertFalse(origin.isForeground, "\(origin)")
        }
    }
}
