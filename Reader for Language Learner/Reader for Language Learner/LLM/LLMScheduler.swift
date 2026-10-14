//
//  LLMScheduler.swift
//  Reader for Language Learner
//
//  A queue for each model running on this Mac (Roadmap v17 Sprint 1, Apple
//  in 1.47.1). LM Studio and Ollama answer on one GPU: two requests at once
//  each run slower, and a long background job — a chapter warm-up, a recap,
//  a batch of glosses — made the word you clicked wait behind it (S0: a word
//  took 5× longer). Requests go out by priority; the app's own work doesn't
//  start while anything you asked for is waiting or running (decision 3) and
//  one of the two slots stays free for you; what has started is not cut off.
//
//  Apple's on-device model answers one request at a time (measured: a short
//  request beside a long one waited until it finished), so it has its own
//  queue with one slot — and there a running background job gives way: it
//  stops when you ask for something and starts over after (1.47.1, user's
//  decision). A request cancelled while waiting — you clicked another word —
//  leaves the queue at once and is never sent. Cloud servers don't queue.
//

import Foundation

/// How soon a request should go out.
nonisolated enum LLMPriority: Int, Comparable, Sendable {
    /// Filling many words.
    case bulk
    /// Work the app starts on its own while you read.
    case background
    /// Quick lookups and the level estimate when you save a word.
    case soon
    /// What you're waiting for on screen.
    case interactive

    static func < (lhs: LLMPriority, rhs: LLMPriority) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Holds back while anything of yours is waiting or running.
    var yieldsToYou: Bool { self <= .background }
}

extension LLMRequestOrigin {
    nonisolated var priority: LLMPriority {
        switch self {
        case .module, .askAI, .grammar, .rewrite, .retell, .story: return .interactive
        case .quickLookup, .cefr:                                  return .soon
        case .warmUp, .recap, .gloss, .prewarm, .speedTest:        return .background
        case .fill:                                                return .bulk
        }
    }
}

/// Which waiting request goes out next. Pure.
nonisolated enum LLMQueuePolicy {
    /// The running request to stop so yours can go out: when something of
    /// yours waits, every slot is taken and one is the app's own work that
    /// may stop (`preemptible`). Index into `running`.
    static func toPreempt(waiting: [LLMPriority], running: [(priority: LLMPriority, preemptible: Bool)],
                          limit: Int) -> Int? {
        guard waiting.contains(where: { !$0.yieldsToYou }), running.count >= max(1, limit) else { return nil }
        return running.indices
            .filter { running[$0].preemptible && running[$0].priority.yieldsToYou }
            .min { running[$0].priority < running[$1].priority }
    }

    /// The index in `waiting` (oldest first) of the request to start now, or
    /// nil to keep everyone waiting.
    static func next(waiting: [LLMPriority], running: [LLMPriority], limit: Int) -> Int? {
        guard running.count < max(1, limit), !waiting.isEmpty else { return nil }
        // Highest priority first; among equals, the one asked for first.
        let index = waiting.indices.max { a, b in
            waiting[a] != waiting[b] ? waiting[a] < waiting[b] : a > b
        }!
        let candidate = waiting[index]
        if candidate.yieldsToYou {
            // Never while yours runs; and one slot always kept free for you,
            // so a word you click goes out at once instead of queuing behind
            // the app's own work.
            if running.contains(where: { !$0.yieldsToYou }) { return nil }
            if limit > 1, running.count >= limit - 1 { return nil }
        }
        return index
    }
}

@MainActor
@Observable
final class LLMScheduler {
    /// Off the main actor: on macOS 15 a main-actor deinit run outside a
    /// task crashes when it releases another one (v16 S0, CI crash reports).
    nonisolated deinit {}

    /// LM Studio / Ollama on this Mac.
    static let shared = LLMScheduler()
    /// Apple's on-device model: one at a time, the app's work gives way.
    static let apple = LLMScheduler(limit: 1, preempts: true)

    /// Requests the model answers at once.
    @ObservationIgnored let limit: Int
    /// A running background request stops for yours.
    @ObservationIgnored let preempts: Bool

    private struct Waiter {
        let id: UUID
        let priority: LLMPriority
        let continuation: CheckedContinuation<Void, Error>
    }

    private struct Running {
        let priority: LLMPriority
        var stop: (@MainActor () -> Void)?
        var stopped = false
    }

    private var waiting: [Waiter] = []
    private var running: [UUID: Running] = [:]

    init(limit: Int = 2, preempts: Bool = false) {
        self.limit = limit
        self.preempts = preempts
    }

    var waitingCount: Int { waiting.count }
    var runningCount: Int { running.count }

    /// Waits for a turn. Throws `CancellationError` if the task is cancelled
    /// before its turn comes; the request then leaves the queue. Pair every
    /// successful call with `release(_:)`.
    func acquire(_ priority: LLMPriority) async throws -> UUID {
        try Task.checkCancellation()
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                waiting.append(Waiter(id: id, priority: priority, continuation: continuation))
                pump()
            }
        } onCancel: {
            Task { @MainActor in self.leave(id) }
        }
        return id
    }

    func release(_ ticket: UUID) {
        guard running.removeValue(forKey: ticket) != nil else { return }
        pump()
    }

    /// How to stop the request holding `ticket` if yours needs the slot.
    /// Only on a queue that `preempts`, and only background work.
    func setStop(_ ticket: UUID, _ stop: @escaping @MainActor () -> Void) {
        guard preempts, running[ticket] != nil else { return }
        running[ticket]?.stop = stop
        pump()
    }

    /// True when the request holding `ticket` was stopped for yours.
    func wasStopped(_ ticket: UUID) -> Bool {
        running[ticket]?.stopped == true
    }

    /// A cancelled request still waiting: out of the queue, never sent.
    private func leave(_ id: UUID) {
        guard let index = waiting.firstIndex(where: { $0.id == id }) else { return }
        waiting.remove(at: index).continuation.resume(throwing: CancellationError())
        pump()
    }

    private func pump() {
        while let index = LLMQueuePolicy.next(waiting: waiting.map(\.priority),
                                              running: running.values.map(\.priority), limit: limit) {
            let waiter = waiting.remove(at: index)
            running[waiter.id] = Running(priority: waiter.priority)
            waiter.continuation.resume()
        }
        guard preempts else { return }
        let entries = Array(running.filter { !$0.value.stopped })
        if let index = LLMQueuePolicy.toPreempt(
            waiting: waiting.map(\.priority),
            running: entries.map { ($0.value.priority, $0.value.stop != nil) },
            limit: limit
        ) {
            let ticket = entries[index].key
            running[ticket]?.stopped = true
            running[ticket]?.stop?()
        }
    }
}
