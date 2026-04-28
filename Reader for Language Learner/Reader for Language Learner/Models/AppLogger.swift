//
//  AppLogger.swift
//  Reader for Language Learner
//
//  Centralized structured logging via os.Logger.
//  Usage: AppLogger.persistence.error("Save failed: \(error)")
//

import Foundation
import os

enum AppLogger {
    private static let subsystem = "com.rell.app"

    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let llm         = Logger(subsystem: subsystem, category: "llm")
    static let ui          = Logger(subsystem: subsystem, category: "ui")
    static let speech      = Logger(subsystem: subsystem, category: "speech")
    static let export      = Logger(subsystem: subsystem, category: "export")
}

enum RELLJSONStore {
    static func load<Value: Decodable>(
        _ type: Value.Type,
        from url: URL,
        storeName: String,
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

extension FileManager {
    /// Returns the RELL Application Support directory, creating it if needed.
    /// Returns nil only if the system Application Support directory is unavailable.
    func rellAppSupportDirectory() -> URL? {
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
