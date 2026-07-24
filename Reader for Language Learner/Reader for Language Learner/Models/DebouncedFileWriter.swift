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

    static func register(_ writer: Flushable) {
        writers.append(Weak(value: writer))
    }

    /// Synchronously writes every pending value. Safe to call from
    /// `applicationWillTerminate` (already on the main thread).
    static func flushAll() {
        for entry in writers { entry.value?.flush() }
        writers.removeAll { $0.value == nil }
    }
}

/// Coalescing, off-main writer for a single JSON file. All state and the encode
/// closure run on the main actor; only the atomic disk write runs off-main.
@MainActor
final class DebouncedFileWriter: Flushable {
    private let fileURL: URL
    private let storeName: String
    private let debounce: TimeInterval
    private let ioQueue: DispatchQueue

    /// Latest encode closure (produces the bytes to persist). Captured on the
    /// main actor and called there; successive schedules replace it, so a burst
    /// collapses to the newest snapshot.
    private var pendingEncode: (() throws -> Data)?
    private var debounceTask: Task<Void, Never>?

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
        pendingEncode = encode
        guard debounce > 0 else { flush(); return }
        guard debounceTask == nil else { return }
        debounceTask = Task { @MainActor [weak self] in
            let interval = self?.debounce ?? 0.5
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.debounceTask = nil
            self.writePendingAsync()
        }
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
        ioQueue.async { [weak self] in
            let error = Self.writeData(data, to: url, storeName: name)
            Task { @MainActor in self?.onResult?(error) }
        }
    }

    /// Writes any pending value synchronously (blocking until the bytes are on
    /// disk). Called at termination and, in write-through mode, on every save.
    func flush() {
        debounceTask?.cancel()
        debounceTask = nil
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
        let error = ioQueue.sync { Self.writeData(data, to: fileURL, storeName: storeName) }
        onResult?(error)
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

    nonisolated private static func writeData(_ data: Data, to url: URL, storeName: String) -> String? {
        do {
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
            return nil
        } catch {
            AppLogger.persistence.error("\(storeName) save failed at \(url.path, privacy: .private): \(error.localizedDescription, privacy: .public)")
            return error.localizedDescription
        }
    }
}
