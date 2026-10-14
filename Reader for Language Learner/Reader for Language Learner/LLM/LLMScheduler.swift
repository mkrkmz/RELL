//
//  LLMScheduler.swift
//  Reader for Language Learner
//
//  One queue for every request to a model running on this Mac (Roadmap v17
//  Sprint 1). LM Studio and Ollama answer on one GPU: two requests at once
//  each run slower, and a long background job — a chapter warm-up, a recap,
//  a batch of glosses — made the word you clicked wait behind it (S0: a word
//  took 5× longer). Requests go out by priority; the app's own work doesn't
//  start while anything you asked for is waiting or running (decision 3), but
//  what has started is never cut off, and one slot stays free for you. A request cancelled while waiting —
//  you clicked another word — leaves the queue at once and is never sent.
//  Apple's model and cloud servers don't queue here.
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

    static let shared = LLMScheduler()

    /// Requests a local server answers at once.
    @ObservationIgnored let limit: Int

    private struct Waiter {
        let id: UUID
        let priority: LLMPriority
        let continuation: CheckedContinuation<Void, Error>
    }

    private var waiting: [Waiter] = []
    private var running: [UUID: LLMPriority] = [:]

    init(limit: Int = 2) {
        self.limit = limit
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

    /// A cancelled request still waiting: out of the queue, never sent.
    private func leave(_ id: UUID) {
        guard let index = waiting.firstIndex(where: { $0.id == id }) else { return }
        waiting.remove(at: index).continuation.resume(throwing: CancellationError())
        pump()
    }

    private func pump() {
        while let index = LLMQueuePolicy.next(waiting: waiting.map(\.priority),
                                              running: Array(running.values), limit: limit) {
            let waiter = waiting.remove(at: index)
            running[waiter.id] = waiter.priority
            waiter.continuation.resume()
        }
    }
}
