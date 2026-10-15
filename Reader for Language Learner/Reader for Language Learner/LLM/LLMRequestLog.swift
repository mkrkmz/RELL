//
//  LLMRequestLog.swift
//  Reader for Language Learner
//
//  Every AI request, timed (Roadmap v17 Sprint 0): what asked (a module, the
//  chapter warm-up, a fill…), which engine answered, how long it waited for
//  its turn, how long until the first word, how long in all and how it
//  ended. Kept in memory only — the last 200 — and never the text sent or
//  received. The answer's footer, the speed test and the diagnostic report
//  read it (S2, S3); each finished request is also logged
//  (`log stream --predicate 'subsystem == "com.rell.app" && category == "llm"'`).
//

import Foundation
import os

/// What asked the model.
nonisolated enum LLMRequestOrigin: String, Sendable, CaseIterable {
    /// An Inspector module; `detail` is the module.
    case module
    case askAI
    case quickLookup
    case cefr
    case fill
    case warmUp
    case recap
    case gloss
    case grammar
    case rewrite
    case retell
    case story
    /// Loading the model before the first word (v17 S1).
    case prewarm
    /// Settings ▸ AI ▸ Speed (v17 S2).
    case speedTest
    /// One of the reader's own modules (v18 S3); the detail is left out —
    /// its name is the reader's text.
    case custom

    /// Work you're waiting for on screen, as opposed to work the app does
    /// on its own while you read.
    var isForeground: Bool {
        switch self {
        case .module, .askAI, .quickLookup, .grammar, .rewrite, .retell, .story, .custom: return true
        case .cefr, .fill, .warmUp, .recap, .gloss, .prewarm, .speedTest: return false
        }
    }
}

nonisolated struct LLMRequestRecord: Identifiable, Equatable, Sendable {
    enum Outcome: Equatable, Sendable {
        case finished
        case cancelled
        case failed(String)
    }

    let id: UUID
    let origin: LLMRequestOrigin
    /// The module's raw value, or nil. Never the word or the passage.
    let detail: String?
    /// "Apple On-Device", "LM Studio", "OpenAI Compatible"…
    let engine: String
    let model: String?
    /// A model on this Mac (LM Studio / Ollama on localhost), which loads
    /// and queues; not Apple's model, not a cloud server.
    var onThisMac = false
    let queuedAt: Date
    var startedAt: Date?
    var firstTokenAt: Date?
    var finishedAt: Date?
    var outcome: Outcome?

    /// Waiting for a free slot before the request went out.
    var wait: TimeInterval? { startedAt.map { $0.timeIntervalSince(queuedAt) } }
    /// From going out to the first word (the whole answer for a non-streamed one).
    var firstToken: TimeInterval? {
        guard let startedAt, let firstTokenAt else { return nil }
        return firstTokenAt.timeIntervalSince(startedAt)
    }
    /// From being asked for to the last word — what you sit through.
    var total: TimeInterval? { finishedAt.map { $0.timeIntervalSince(queuedAt) } }
}

@MainActor
@Observable
final class LLMRequestLog {
    /// Off the main actor: on macOS 15 a main-actor deinit run outside a
    /// task crashes when it releases another one (v16 S0, CI crash reports).
    nonisolated deinit {}

    static let shared = LLMRequestLog()
    static let capacity = 200

    /// Oldest first.
    private(set) var records: [LLMRequestRecord] = []

    private let clock: () -> Date

    init(clock: @escaping () -> Date = Date.init) {
        self.clock = clock
    }

    func begin(origin: LLMRequestOrigin, detail: String?, engine: String, model: String?,
               onThisMac: Bool = false) -> UUID {
        let record = LLMRequestRecord(id: UUID(), origin: origin, detail: detail, engine: engine,
                                      model: model, onThisMac: onThisMac, queuedAt: clock())
        records.append(record)
        if records.count > Self.capacity { records.removeFirst(records.count - Self.capacity) }
        return record.id
    }

    func started(_ id: UUID) {
        update(id) { if $0.startedAt == nil { $0.startedAt = self.clock() } }
    }

    func firstToken(_ id: UUID) {
        update(id) { if $0.firstTokenAt == nil { $0.firstTokenAt = self.clock() } }
    }

    func finish(_ id: UUID, _ outcome: LLMRequestRecord.Outcome) {
        update(id) { record in
            guard record.outcome == nil else { return }
            let now = self.clock()
            if record.firstTokenAt == nil, outcome == .finished { record.firstTokenAt = now }
            record.finishedAt = now
            record.outcome = outcome
        }
        if let record = records.last(where: { $0.id == id }) { Self.log(record) }
    }

    /// Requests that were asked for but never went out — dropped while
    /// waiting for their turn (a new word replaced them).
    var neverSent: [LLMRequestRecord] {
        records.filter { $0.startedAt == nil && $0.outcome != nil }
    }

    private func update(_ id: UUID, _ change: (inout LLMRequestRecord) -> Void) {
        guard let index = records.lastIndex(where: { $0.id == id }) else { return }
        change(&records[index])
    }

    private static func log(_ record: LLMRequestRecord) {
        func seconds(_ value: TimeInterval?) -> String {
            value.map { String(format: "%.2f", $0) } ?? "-"
        }
        let what = [record.origin.rawValue, record.detail].compactMap { $0 }.joined(separator: "/")
        let engine = [record.engine, record.model].compactMap { $0 }.joined(separator: " · ")
        let outcome: String
        switch record.outcome {
        case .finished:          outcome = "finished"
        case .cancelled:         outcome = "cancelled"
        case .failed(let error): outcome = "failed: \(error)"
        case nil:                outcome = "open"
        }
        AppLogger.llm.info("""
            request \(what, privacy: .public) via \(engine, privacy: .public): \
            wait \(seconds(record.wait), privacy: .public)s, \
            first \(seconds(record.firstToken), privacy: .public)s, \
            total \(seconds(record.total), privacy: .public)s, \(outcome, privacy: .public)
            """)
    }
}

// MARK: - Recording a provider

/// Times every request that goes through `base` in `LLMRequestLog`. The
/// request counts as asked for when this wrapper is made — make it where the
/// request is decided, before any queue — and as sent when `chat` or
/// `stream` is called.
struct RecordedLLMProvider: LLMProvider {
    let base: any LLMProvider
    let id: UUID
    let log: LLMRequestLog
    /// The queue for a model on this Mac (v17 S1); nil: no queue (Apple's
    /// model, a cloud server).
    var queue: LLMScheduler? = nil
    var priority: LLMPriority = .interactive

    func chat(system: String, user: String, temperature: Double, maxTokens: Int, topP: Double) async throws -> String {
        let base = base
        // A whole answer at once: background work can stop for yours and
        // start over (Apple's queue) — nothing was shown yet.
        return try await whenItsTurn(canRestart: true) {
            try await base.chat(system: system, user: user, temperature: temperature,
                                maxTokens: maxTokens, topP: topP)
        }
    }

    @discardableResult
    func stream(
        system: String, user: String, temperature: Double, maxTokens: Int, topP: Double,
        onToken: @MainActor @escaping (String) -> Void
    ) async throws -> LLMFinishReason? {
        let id = id
        let log = log
        let base = base
        return try await whenItsTurn(canRestart: false) {
            try await base.stream(system: system, user: user, temperature: temperature,
                                  maxTokens: maxTokens, topP: topP) { token in
                log.firstToken(id)
                onToken(token)
            }
        }
    }

    /// Waits for the queue (if any), then sends — timing both.
    /// `canRestart`: a background request on a queue that preempts may be
    /// stopped for yours; it then waits its turn again and starts over.
    private func whenItsTurn<Result: Sendable>(
        canRestart: Bool,
        _ send: @escaping () async throws -> Result
    ) async throws -> Result {
        do {
            while true {
                let ticket = try await queue?.acquire(priority)
                log.started(id)
                guard let queue, let ticket, canRestart, queue.preempts, priority.yieldsToYou else {
                    defer { if let ticket { queue?.release(ticket) } }
                    let result = try await send()
                    return finished(result)
                }
                let work = Task { try await send() }
                queue.setStop(ticket) { work.cancel() }
                do {
                    let result = try await withTaskCancellationHandler {
                        try await work.value
                    } onCancel: {
                        work.cancel()
                    }
                    queue.release(ticket)
                    return finished(result)
                } catch where queue.wasStopped(ticket) && !Task.isCancelled {
                    queue.release(ticket)   // yours goes out; this one starts over
                    continue
                } catch {
                    queue.release(ticket)
                    throw error
                }
            }
        } catch {
            log.finish(id, Self.outcome(for: error))
            throw error
        }
    }

    private func finished<Result: Sendable>(_ result: Result) -> Result {
        log.finish(id, .finished)
        if let queue, !queue.preempts { LocalModelWarmth.requestFinished() }   // a local server
        return result
    }

    /// Ends the record of a request that was dropped before it went out.
    func dropIfNotSent() {
        log.dropIfNotSent(id)
    }

    static func outcome(for error: Error) -> LLMRequestRecord.Outcome {
        if error is CancellationError || (error as? URLError)?.code == .cancelled || Task.isCancelled {
            return .cancelled
        }
        // A short kind, never the message (it can quote the request).
        if let urlError = error as? URLError { return .failed("URLError \(urlError.code.rawValue)") }
        let nsError = error as NSError
        return .failed("\(nsError.domain) \(nsError.code)")
    }
}

extension LLMRequestLog {
    /// Marks a request that never went out as cancelled; one that did is
    /// left to finish on its own.
    func record(_ id: UUID) -> LLMRequestRecord? {
        records.last { $0.id == id }
    }

    func dropIfNotSent(_ id: UUID) {
        guard let record = records.last(where: { $0.id == id }),
              record.startedAt == nil, record.outcome == nil else { return }
        finish(id, .cancelled)
    }

    /// `provider` recorded as one request from `origin`. `route` names the
    /// engine: Apple's model, or the configured provider and its model. A
    /// model on this Mac waits its turn in `queue` (v17 S1); Apple's model
    /// in `appleQueue` (1.47.1).
    func recording(
        _ provider: any LLMProvider,
        origin: LLMRequestOrigin,
        detail: String? = nil,
        route: LLMRoute,
        queue: LLMScheduler = .shared,
        appleQueue: LLMScheduler = .apple
    ) -> RecordedLLMProvider {
        let engine: String
        let model: String?
        let onThisMac: Bool
        let lane: LLMScheduler?
        switch route {
        case .appleOnDevice:
            engine = AppleOnDevice.providerLabel
            model = nil
            onThisMac = true
            lane = appleQueue
        case .configured:
            let configuration = LLMConfiguration()
            engine = configuration.providerType.rawValue
            model = configuration.model
            onThisMac = configuration.runsOnThisMac
            lane = onThisMac ? queue : nil
        }
        let id = begin(origin: origin, detail: detail, engine: engine, model: model, onThisMac: onThisMac)
        return RecordedLLMProvider(base: provider, id: id, log: self, queue: lane, priority: origin.priority)
    }
}
