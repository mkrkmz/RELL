//
//  LLMSchedulerTests.swift
//  Reader for Language LearnerTests
//
//  v17 Sprint 1 — one queue for a model on this Mac: what you asked for goes
//  first, the app's own work waits for it and leaves a slot free, a request
//  cancelled while waiting is never sent, and the model is kept loaded.
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class LLMSchedulerTests: XCTestCase {

    // MARK: Policy

    func testHighestPriorityGoesFirstThenTheOldest() {
        XCTAssertEqual(LLMQueuePolicy.next(waiting: [.bulk, .soon, .interactive, .interactive], running: [], limit: 2), 2)
        XCTAssertEqual(LLMQueuePolicy.next(waiting: [.soon, .soon], running: [], limit: 2), 0)
        XCTAssertNil(LLMQueuePolicy.next(waiting: [.interactive], running: [.soon, .soon], limit: 2), "both slots busy")
    }

    func testTheAppsOwnWorkWaitsWhileYoursRuns() {
        XCTAssertNil(LLMQueuePolicy.next(waiting: [.background], running: [.interactive], limit: 2))
        XCTAssertNil(LLMQueuePolicy.next(waiting: [.bulk], running: [.soon], limit: 2))
        XCTAssertEqual(LLMQueuePolicy.next(waiting: [.background], running: [], limit: 2), 0)
        XCTAssertNil(LLMQueuePolicy.next(waiting: [.background], running: [.interactive], limit: 3),
                     "even with slots to spare")
    }

    func testOneSlotStaysFreeForYou() {
        XCTAssertNil(LLMQueuePolicy.next(waiting: [.background], running: [.background], limit: 2),
                     "a second warm-up would take the slot your next word needs")
        XCTAssertEqual(LLMQueuePolicy.next(waiting: [.background, .interactive], running: [.background], limit: 2), 1)
        XCTAssertEqual(LLMQueuePolicy.next(waiting: [.background], running: [], limit: 1), 0,
                       "with one slot the app's work still runs when you ask for nothing")
    }

    // MARK: Queue

    func testYourWordOvertakesTheAppsWorkAndIsNeverBehindIt() async throws {
        let queue = LLMScheduler(limit: 2)
        let warmUp = try await queue.acquire(.background)
        let order = Order()
        let gloss = Task { let t = try await queue.acquire(.background); order.items.append("gloss"); return t }
        let word = Task { let t = try await queue.acquire(.interactive); order.items.append("word"); return t }
        // Bounded: a queue that got this wrong would keep the word waiting forever.
        try await waitUntil { order.items == ["word"] }
        guard order.items == ["word"] else {
            XCTFail("the word should go out while the warm-up still runs; got \(order.items)")
            word.cancel(); gloss.cancel(); return
        }
        let wordTicket = try await word.value
        XCTAssertEqual(queue.waitingCount, 1)

        queue.release(warmUp)
        await Task.yield()
        guard queue.waitingCount == 1 else {
            XCTFail("the gloss must wait while your word runs")
            gloss.cancel(); return
        }
        queue.release(wordTicket)
        queue.release(try await gloss.value)
        XCTAssertEqual(order.items, ["word", "gloss"])
        XCTAssertEqual(queue.runningCount, 0)
    }

    func testARequestCancelledWhileWaitingLeavesAtOnce() async throws {
        let queue = LLMScheduler(limit: 1)
        let busy = try await queue.acquire(.interactive)
        let stale = Task { try await queue.acquire(.interactive) }
        try await waitUntil { queue.waitingCount == 1 }
        stale.cancel()
        do {
            _ = try await stale.value
            XCTFail("a cancelled request must not get a turn")
        } catch is CancellationError {}
        XCTAssertEqual(queue.waitingCount, 0)
        queue.release(busy)
        XCTAssertEqual(queue.runningCount, 0)
    }

    func testTheWaitIsRecordedAndADroppedRequestIsNeverSent() async throws {
        let queue = LLMScheduler(limit: 1)
        let log = LLMRequestLog()
        let busy = try await queue.acquire(.interactive)

        let first = RecordedLLMProvider(base: Echo(), id: log.begin(origin: .module, detail: nil, engine: "x", model: nil),
                                        log: log, queue: queue, priority: .interactive)
        let dropped = RecordedLLMProvider(base: Echo(), id: log.begin(origin: .module, detail: nil, engine: "x", model: nil),
                                          log: log, queue: queue, priority: .interactive)
        let sent = Task { try await first.chat(system: "", user: "a", temperature: 0, maxTokens: 1, topP: 1) }
        let stale = Task { try await dropped.chat(system: "", user: "b", temperature: 0, maxTokens: 1, topP: 1) }
        try await waitUntil { queue.waitingCount == 2 }
        stale.cancel()
        queue.release(busy)

        let answer = try await sent.value
        XCTAssertEqual(answer, "a")
        _ = try? await stale.value
        XCTAssertNotNil(log.records[0].startedAt)
        XCTAssertEqual(log.records[0].outcome, .finished)
        XCTAssertEqual(log.neverSent.map(\.id), [dropped.id])
    }

    func testOnlyAModelOnThisMacQueues() {
        let onMac = { LLMConfiguration.runsOnThisMac(type: $0, serverURL: $1, model: $2) }
        XCTAssertTrue(onMac(.ollama, "http://127.0.0.1:11434", "gemma4:12b"))
        XCTAssertTrue(onMac(.lmStudio, "http://localhost:1234", "google/gemma-4-e4b"))
        XCTAssertFalse(onMac(.ollama, "http://127.0.0.1:11434", "gemma4:31b-cloud"), "runs remotely")
        XCTAssertFalse(onMac(.openAI, "http://127.0.0.1:8080", "x"))
        XCTAssertFalse(onMac(.ollama, "http://192.168.1.5:11434", "gemma4:12b"))
        XCTAssertEqual(LLMRequestOrigin.module.priority, .interactive)
        XCTAssertEqual(LLMRequestOrigin.warmUp.priority, .background)
        XCTAssertEqual(LLMRequestOrigin.prewarm.priority, .background)
        XCTAssertEqual(LLMRequestOrigin.fill.priority, .bulk)
    }

    // MARK: Warmth

    func testOllamaIsAskedToKeepTheModelWithoutGenerating() throws {
        let request = try XCTUnwrap(LocalModelWarmth.ollamaKeepAlive(serverURL: "http://127.0.0.1:11434", model: "gemma4:12b"))
        XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:11434/api/generate")
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: String])
        XCTAssertEqual(body, ["model": "gemma4:12b", "keep_alive": "30m"], "no prompt: load only")
    }

    func testAtMostOnePingAMinute() {
        let now = Date()
        XCTAssertTrue(LocalModelWarmth.shouldPing(last: nil, now: now))
        XCTAssertFalse(LocalModelWarmth.shouldPing(last: now.addingTimeInterval(-30), now: now))
        XCTAssertTrue(LocalModelWarmth.shouldPing(last: now.addingTimeInterval(-61), now: now))
    }

    private final class Order { var items: [String] = [] }

    /// Polls for up to a second instead of waiting on a task that a broken
    /// queue would never let finish.
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() { try await Task.sleep(for: .milliseconds(5)) }
    }

    private struct Echo: LLMProvider {
        func chat(system: String, user: String, temperature: Double, maxTokens: Int, topP: Double) async throws -> String { user }
        func stream(system: String, user: String, temperature: Double, maxTokens: Int, topP: Double,
                    onToken: @MainActor @escaping (String) -> Void) async throws -> LLMFinishReason? {
            onToken(user)
            return .stop
        }
    }
}
