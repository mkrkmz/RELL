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
