//
//  AsyncLimiter.swift
//  Reader for Language Learner
//
//  Bounded-concurrency gate for LLM requests. Local servers (LM Studio,
//  Ollama) process requests on a single GPU context — firing many streams
//  at once makes every one of them slower. Callers acquire a slot before
//  starting a request and release it when the stream finishes.
//

import Foundation

actor AsyncLimiter {
    private let limit: Int
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    func acquire() async {
        if active < limit {
            active += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func releaseSlot() {
        if waiters.isEmpty {
            active -= 1
        } else {
            // Hand the slot directly to the next waiter; `active` stays the same.
            waiters.removeFirst().resume()
        }
    }

    /// Safe to call from any context, including `defer` blocks.
    nonisolated func release() {
        Task { await self.releaseSlot() }
    }
}
