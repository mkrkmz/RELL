//
//  AppLogger.swift
//  Reader for Language Learner
//
//  Centralized structured logging via os.Logger.
//  Usage: AppLogger.persistence.error("Save failed: \(error)")
//

import Foundation
import os

nonisolated enum AppLogger {
    private static let subsystem = "com.rell.app"

    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let llm         = Logger(subsystem: subsystem, category: "llm")
    static let ui          = Logger(subsystem: subsystem, category: "ui")
    static let speech      = Logger(subsystem: subsystem, category: "speech")
    static let export      = Logger(subsystem: subsystem, category: "export")
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
}

enum RELLJSONStore {
    /// Loads a store's file, or `defaultValue` when there is none.
    ///
    /// A file that exists but can't be read or decoded is **moved aside**
    /// (`PersistenceRecovery.quarantine`) before the default is returned.
    /// Every store writes its whole value back on the next mutation, so
    /// returning an empty default while leaving the file in place used to
    /// overwrite the user's entire vocabulary with the one word they saved
    /// next. `userVisible: false` quarantines without telling the user —
    /// for regenerable data such as the LLM output cache.
    static func load<Value: Decodable>(
        _ type: Value.Type,
        from url: URL,
        storeName: String,
        userVisible: Bool = true,
        defaultValue: @autoclosure () -> Value
    ) -> Value {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return defaultValue()
        }

        do {
            let data = try Data(contentsOf: url)
            guard !data.isEmpty else {
                AppLogger.persistence.warning("\(storeName) load skipped empty file at \(url.path, privacy: .private)")
                return defaultValue()
            }
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            AppLogger.persistence.error("\(storeName) load failed at \(url.path, privacy: .private): \(error.localizedDescription, privacy: .public)")
            PersistenceRecovery.quarantine(url, userVisible: userVisible)
            return defaultValue()
        }
    }

    static func save<Value: Encodable>(
        _ value: Value,
        to url: URL,
        storeName: String
    ) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(value)
        try data.write(to: url, options: [.atomic])
    }
}

// MARK: - App Support Directory

nonisolated enum RELLProcess {
    /// True when this process is the host of a unit-test run. The test
    /// target runs inside the app, so without this every `xcodebuild test`
    /// started a second RELL on the user's real data — alongside their own
    /// copy, if it was open (v13 Sprint 5).
    static let isTestHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    /// Per-run data folder for the test host.
    static let testDataDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("RELL-test-host-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
}

extension FileManager {
    /// Returns the RELL Application Support directory, creating it if needed.
    /// Returns nil only if the system Application Support directory is unavailable.
    /// Under a test host it's a throwaway folder instead (`RELLProcess`).
    func rellAppSupportDirectory() -> URL? {
        if RELLProcess.isTestHost {
            let folder = RELLProcess.testDataDirectory
            try? createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }
        guard let appSupport = urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            AppLogger.persistence.critical("Application Support directory not available")
            return nil
        }
        let rell = appSupport.appendingPathComponent("RELL", isDirectory: true)
        do {
            try createDirectory(at: rell, withIntermediateDirectories: true)
        } catch {
            AppLogger.persistence.error("Failed to create RELL directory: \(error.localizedDescription)")
        }
        return rell
    }
}
