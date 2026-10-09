//
//  DebouncedFileWriter.swift
//  Reader for Language Learner
//
//  Off-main, debounced JSON persistence for the hot stores (SavedWordsStore
//  above all — it re-encodes and rewrites its whole array on every mutation).
//  A burst of rapid mutations (a review session, a bulk edit) coalesces into a
//  single background disk write instead of blocking the main actor on each one.
//
//  The project builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so the
//  encode closure stays on the main actor (where a model's synthesized
//  `Encodable` conformance is valid) and only the atomic `Data.write` — the
//  part that actually hitches — runs on a utility queue. Encoding happens once
//  per debounce window, not once per mutation, so the main-actor cost is
//  bounded regardless of how fast the store is mutated.
//
//  Durability is preserved by `flush()`, which writes synchronously and is
//  called on app termination via `PersistenceCoordinator.flushAll()`. Tests
//  construct their stores in write-through mode (debounce 0) so the existing
//  "mutate then reload from disk" assertions stay deterministic.
//

import Foundation
import os

/// A store whose pending write can be forced to disk synchronously.
@MainActor
protocol Flushable: AnyObject {
    func flush()
    func discardPending()
}

/// Flushes every live writer at a single point (app termination). Writers
/// register themselves weakly on init, so a store going away drops out on its
/// own without an explicit unregister.
@MainActor
enum PersistenceCoordinator {
    private struct Weak {
        weak var value: Flushable?
    }

    private static var writers: [Weak] = []

    /// Set once a backup restore has replaced the files on disk: from then
    /// until the relaunch, nothing in memory may be written back over them —
    /// not a pending debounce, not the termination flush, not a session that
    /// ends because its window closes.
    private(set) static var isSuspended = false

    static func register(_ writer: Flushable) {
        writers.append(Weak(value: writer))
    }

    /// Synchronously writes every pending value. Safe to call from
    /// `applicationWillTerminate` (already on the main thread).
    static func flushAll() {
        for entry in writers { entry.value?.flush() }
        writers.removeAll { $0.value == nil }
    }

    /// Drops every pending write and refuses new ones for the rest of the
    /// process. Used right before a restore swaps the files underneath.
    static func discardPendingWrites() {
        isSuspended = true
        for entry in writers { entry.value?.discardPending() }
    }

    #if DEBUG
    /// Tests only: a restore test suspends writes for the whole process.
    static func resumeWritesForTesting() { isSuspended = false }
    #endif
}

/// Coalescing, off-main writer for a single JSON file. All state and the encode
/// closure run on the main actor; only the atomic disk write runs off-main.
@MainActor
final class DebouncedFileWriter: Flushable {
    /// Off the main actor: on macOS 15 a main-actor deinit run outside a
    /// task crashes when it releases another one (v16 S0, CI crash reports).
    nonisolated deinit {}

    private let fileURL: URL
    private let storeName: String
    private let debounce: TimeInterval
    private let ioQueue: DispatchQueue

    /// Latest encode closure (produces the bytes to persist). Captured on the
    /// main actor and called there; successive schedules replace it, so a burst
    /// collapses to the newest snapshot.
    private var pendingEncode: (() throws -> Data)?
    /// Debounce timer. A cancellable GCD work item, deliberately NOT a Swift
    /// `Task`: a detached `Task { @MainActor … }` here congested the main-actor
    /// cooperative pool on core-constrained CI runners and hung the test host.
    /// Pure GCD keeps scheduling deterministic and off the concurrency runtime.
    private var pendingWorkItem: DispatchWorkItem?

    /// Every encoded snapshot gets the next number; `lastWritten` records the
    /// newest one on disk. The debounced write (on `ioQueue`) and `flush()`
    /// (on the calling thread) both write under `lastWritten`'s lock and skip
    /// anything older than what's already there — without it, a snapshot
    /// still in flight when the app quits could land AFTER the termination
    /// flush and replace the newer data with older data.
    private var nextGeneration: UInt64 = 0
    private let lastWritten = OSAllocatedUnfairLock<UInt64>(initialState: 0)

    /// Called on the main actor after each write with the failure message, or
    /// `nil` on success — lets a store surface `saveError` without polling.
    var onResult: ((String?) -> Void)?

    /// - Parameter debounce: seconds to coalesce writes over. `0` makes every
    ///   `schedule` write through synchronously — used by tests for
    ///   deterministic reload-from-disk assertions.
    init(fileURL: URL, storeName: String, debounce: TimeInterval = 0.5) {
        self.fileURL = fileURL
        self.storeName = storeName
        self.debounce = debounce
        self.ioQueue = DispatchQueue(label: "com.rell.persistence.\(storeName)", qos: .utility)
        PersistenceCoordinator.register(self)
    }

    /// Records how to encode the latest value and schedules a write. Successive
    /// calls within the debounce window collapse into one write of the newest.
    func schedule(_ encode: @escaping () throws -> Data) {
        guard !PersistenceCoordinator.isSuspended else { return }
        pendingEncode = encode
        guard debounce > 0 else { flush(); return }
        guard pendingWorkItem == nil else { return }
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pendingWorkItem = nil
                self.writePendingAsync()
            }
        }
        pendingWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: item)
    }

    private func writePendingAsync() {
        guard let encode = pendingEncode else { return }
        pendingEncode = nil
        let data: Data
        do {
            data = try encode()
        } catch {
            AppLogger.persistence.error("\(self.storeName) encode failed: \(error.localizedDescription, privacy: .public)")
            onResult?(error.localizedDescription)
            return
        }
        let url = fileURL
        let name = storeName
        let generation = takeGeneration()
        let lastWritten = lastWritten
        ioQueue.async { [weak self] in
            let error = Self.writeData(data, generation: generation, lastWritten: lastWritten, to: url, storeName: name)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.onResult?(error) }
            }
        }
    }

    /// Writes any pending value synchronously (blocking until the bytes are on
    /// disk). Called at termination and, in write-through mode, on every save.
    ///
    /// The write runs DIRECTLY on the calling thread — never via `ioQueue.sync`.
    /// Blocking the main actor's thread on a Dispatch queue deadlocks under the
    /// Swift-concurrency runtime on core-constrained CI runners (the whole
    /// write-through test suite hung there). The debounced path stays off-main
    /// via `ioQueue.async`; `pendingEncode` is consumed on the main actor, so a
    /// direct flush and an in-flight async write can never double-write.
    func flush() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
        guard !PersistenceCoordinator.isSuspended else {
            pendingEncode = nil
            return
        }
        guard let encode = pendingEncode else { return }
        pendingEncode = nil
        let data: Data
        do {
            data = try encode()
        } catch {
            AppLogger.persistence.error("\(self.storeName) encode failed: \(error.localizedDescription, privacy: .public)")
            onResult?(error.localizedDescription)
            return
        }
        let error = Self.writeData(
            data, generation: takeGeneration(), lastWritten: lastWritten,
            to: fileURL, storeName: storeName
        )
        onResult?(error)
    }

    #if DEBUG
    /// Tests only: holds the background queue so a debounced write can be
    /// left in flight while `flush()` runs.
    func suspendIOForTesting() { ioQueue.suspend() }
    func resumeIOForTesting() { ioQueue.resume() }
    #endif

    func discardPending() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
        pendingEncode = nil
    }

    private func takeGeneration() -> UInt64 {
        nextGeneration += 1
        return nextGeneration
    }

    /// Resolves the JSON store's file URL and a matching writer. A test
    /// override (`customFileURL`) forces write-through (debounce 0) so
    /// reload-from-disk assertions stay deterministic; the app path debounces
    /// off-main. `canLoad` is false only when Application Support is
    /// unavailable and the store degrades to a throwaway temp file.
    static func forAppSupport(
        filename: String,
        storeName: String,
        customFileURL: URL?
    ) -> (writer: DebouncedFileWriter, url: URL, canLoad: Bool) {
        if let customFileURL {
            return (DebouncedFileWriter(fileURL: customFileURL, storeName: storeName, debounce: 0), customFileURL, true)
        }
        if let directory = FileManager.default.rellAppSupportDirectory() {
            let url = directory.appendingPathComponent(filename)
            return (DebouncedFileWriter(fileURL: url, storeName: storeName), url, true)
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        return (DebouncedFileWriter(fileURL: url, storeName: storeName), url, false)
    }

    /// Writes `data` unless a newer generation is already on disk. Holding
    /// the lock across the write orders the two writers; it is a plain lock,
    /// never a `Dispatch` sync onto `ioQueue` (see `flush()`).
    nonisolated private static func writeData(
        _ data: Data,
        generation: UInt64,
        lastWritten: OSAllocatedUnfairLock<UInt64>,
        to url: URL,
        storeName: String
    ) -> String? {
        lastWritten.withLock { newest -> String? in
            guard generation > newest else { return nil }
            do {
                let directory = url.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try data.write(to: url, options: [.atomic])
                newest = generation
                return nil
            } catch {
                Logger(subsystem: "com.rell.app", category: "persistence")
                    .error("\(storeName) save failed at \(url.path, privacy: .private): \(error.localizedDescription, privacy: .public)")
                return error.localizedDescription
            }
        }
    }
}
