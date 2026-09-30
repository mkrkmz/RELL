//
//  PersistenceSafety.swift
//  Reader for Language Learner
//
//  The two guarantees behind "RELL never silently loses your data":
//
//  1. `PersistenceRecovery` — a store file that can't be read is moved aside
//     byte-for-byte before the store starts empty, and the user is told.
//     (Before v1.39 the empty store's first save overwrote it.)
//  2. `PersistenceBackup` — a copy of every user-data file once a day, the
//     last seven kept, plus export/import of the whole set to a folder the
//     user picks. Restoring swaps the files in and relaunches, because every
//     store holds its data in memory and would write it straight back.
//

import AppKit
import Foundation
import os

// MARK: - Recovery

@MainActor
enum PersistenceRecovery {
    struct QuarantinedFile: Identifiable, Equatable {
        let id = UUID()
        /// Where the unreadable file now lives, untouched.
        let url: URL
        /// The store's file name, e.g. `saved_words.json`.
        let originalName: String

        var localizedStoreName: String {
            PersistenceBackup.localizedName(forFile: originalName)
        }
    }

    /// Files quarantined this launch that the user hasn't been told about.
    private(set) static var pending: [QuarantinedFile] = []

    /// Moves `url` to `<name>.corrupt-<timestamp>.json` in the same folder.
    /// A rename keeps the bytes exactly as they were, and works even when
    /// the content itself can't be read.
    @discardableResult
    static func quarantine(_ url: URL, userVisible: Bool = true, now: Date = Date()) -> URL? {
        let fileManager = FileManager.default
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.isEmpty ? "json" : url.pathExtension
        let stamp = Self.timestamp(now)
        var destination = url.deletingLastPathComponent()
            .appendingPathComponent("\(base).corrupt-\(stamp).\(ext)")
        var suffix = 2
        while fileManager.fileExists(atPath: destination.path) {
            destination = url.deletingLastPathComponent()
                .appendingPathComponent("\(base).corrupt-\(stamp)-\(suffix).\(ext)")
            suffix += 1
        }
        do {
            try fileManager.moveItem(at: url, to: destination)
        } catch {
            AppLogger.persistence.critical("Could not quarantine \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
        AppLogger.persistence.error("Quarantined unreadable \(url.lastPathComponent, privacy: .public) as \(destination.lastPathComponent, privacy: .public)")
        if userVisible {
            pending.append(QuarantinedFile(url: destination, originalName: url.lastPathComponent))
        }
        return destination
    }

    /// Returns the files the user hasn't been told about and clears the list,
    /// so only the first window that asks shows the alert.
    static func takePending() -> [QuarantinedFile] {
        defer { pending.removeAll() }
        return pending
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}

// MARK: - Backups

@MainActor
enum PersistenceBackup {
    /// User data worth backing up. Covers and the LLM output cache are
    /// regenerable and deliberately left out.
    static let dataFiles = [
        "saved_words.json",
        "reading_sessions.json",
        "pdf_notes.json",
        "pdf_highlights.json",
        "epub_notes.json",
        "epub_highlights.json",
        "epub_bookmarks.json",
        "recent_documents.json",
        "library_collections.json",
        WordEncounterStore.fileName,
    ]

    /// PDF bookmarks live in UserDefaults; a backup carries them as a file.
    static let pdfBookmarksFile = "pdf_bookmarks.json"
    static let pdfBookmarksDefaultsKey = "rell_pdf_bookmarks_v1"

    static let backupsFolderName = "Backups"
    static let keptDailyBackups = 7

    struct Backup: Identifiable, Equatable {
        let url: URL
        let date: Date
        var id: URL { url }
    }

    static func localizedName(forFile name: String) -> String {
        switch name {
        case "saved_words.json":         return String(localized: "Saved words")
        case "reading_sessions.json":    return String(localized: "Reading history")
        case "pdf_notes.json", "epub_notes.json":
            return String(localized: "Notes")
        case "pdf_highlights.json", "epub_highlights.json":
            return String(localized: "Highlights")
        case "epub_bookmarks.json", pdfBookmarksFile:
            return String(localized: "Bookmarks")
        case "recent_documents.json":    return String(localized: "Library")
        case "library_collections.json": return String(localized: "Collections")
        case WordEncounterStore.fileName: return String(localized: "Word encounters")
        default:                         return name
        }
    }

    // MARK: Daily

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Copies today's data into `Backups/<yyyy-MM-dd>/` unless that folder
    /// already exists, then prunes to the newest `keptDailyBackups`. Runs
    /// after the stores have loaded, so a file quarantined this launch has
    /// already been moved out of the way and never replaces a good copy.
    ///
    /// `dataDirectory: nil` means RELL's Application Support folder — tests
    /// pass a temporary one.
    @discardableResult
    static func runDailyIfNeeded(
        dataDirectory: URL? = nil,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) -> URL? {
        guard let dataDirectory = dataDirectory ?? FileManager.default.rellAppSupportDirectory() else { return nil }
        let root = dataDirectory.appendingPathComponent(backupsFolderName, isDirectory: true)
        let today = root.appendingPathComponent(dayFormatter.string(from: now), isDirectory: true)
        guard !FileManager.default.fileExists(atPath: today.path) else { return nil }
        do {
            try writeSnapshot(from: dataDirectory, defaults: defaults, to: today)
        } catch {
            AppLogger.persistence.error("Daily backup failed: \(error.localizedDescription, privacy: .public)")
            try? FileManager.default.removeItem(at: today)
            return nil
        }
        prune(root: root)
        return today
    }

    static func dailyBackups(
        dataDirectory: URL? = nil
    ) -> [Backup] {
        guard let dataDirectory = dataDirectory ?? FileManager.default.rellAppSupportDirectory() else { return [] }
        let root = dataDirectory.appendingPathComponent(backupsFolderName, isDirectory: true)
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil
        )) ?? []
        return folders
            .compactMap { url in
                dayFormatter.date(from: url.lastPathComponent).map { Backup(url: url, date: $0) }
            }
            .sorted { $0.date > $1.date }
    }

    private static func prune(root: URL) {
        let backups = dailyBackups(dataDirectory: root.deletingLastPathComponent())
        for stale in backups.dropFirst(keptDailyBackups) {
            try? FileManager.default.removeItem(at: stale.url)
        }
    }

    // MARK: Snapshot

    /// Writes every existing data file (and the PDF bookmarks) into
    /// `destination`, creating it. Files that don't exist yet are skipped.
    static func writeSnapshot(from dataDirectory: URL, defaults: UserDefaults, to destination: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        for name in dataFiles {
            let source = dataDirectory.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try fileManager.copyItem(at: source, to: destination.appendingPathComponent(name))
        }
        if let bookmarks = defaults.data(forKey: pdfBookmarksDefaultsKey) {
            try bookmarks.write(to: destination.appendingPathComponent(pdfBookmarksFile), options: .atomic)
        }
    }

    /// True when `folder` holds at least one file RELL knows how to restore.
    static func isBackupFolder(_ folder: URL) -> Bool {
        (dataFiles + [pdfBookmarksFile]).contains {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
    }

    // MARK: Restore

    /// Replaces the live data with `folder`'s. The current data is first
    /// saved as its own dated backup, so a restore can itself be undone.
    ///
    /// Pending debounced writes are dropped rather than flushed — flushing
    /// would write the in-memory data the user is replacing. The caller must
    /// relaunch (`relaunch()`) straight after: the stores still hold the old
    /// data in memory and would write it back on the next change.
    static func restore(
        from folder: URL,
        dataDirectory: URL? = nil,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) throws {
        guard let dataDirectory = dataDirectory ?? FileManager.default.rellAppSupportDirectory() else {
            throw CocoaError(.fileNoSuchFile)
        }
        let fileManager = FileManager.default

        let safetyCopy = dataDirectory
            .appendingPathComponent(backupsFolderName, isDirectory: true)
            .appendingPathComponent("before-restore-\(PersistenceRecovery.timestamp(now))", isDirectory: true)
        try writeSnapshot(from: dataDirectory, defaults: defaults, to: safetyCopy)

        PersistenceCoordinator.discardPendingWrites()

        for name in dataFiles {
            let source = folder.appendingPathComponent(name)
            let target = dataDirectory.appendingPathComponent(name)
            if fileManager.fileExists(atPath: source.path) {
                let data = try Data(contentsOf: source)
                try data.write(to: target, options: .atomic)
            } else if fileManager.fileExists(atPath: target.path) {
                // Absent from the backup means empty at the time it was taken.
                try fileManager.removeItem(at: target)
            }
        }
        let bookmarks = folder.appendingPathComponent(pdfBookmarksFile)
        if let data = try? Data(contentsOf: bookmarks) {
            defaults.set(data, forKey: pdfBookmarksDefaultsKey)
        } else {
            defaults.removeObject(forKey: pdfBookmarksDefaultsKey)
        }
    }

    // MARK: Export

    /// Writes a complete copy into a new `RELL Backup <date>` folder inside
    /// `parent` and returns it.
    static func export(
        to parent: URL,
        dataDirectory: URL? = nil,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) throws -> URL {
        guard let dataDirectory = dataDirectory ?? FileManager.default.rellAppSupportDirectory() else {
            throw CocoaError(.fileNoSuchFile)
        }
        var destination = parent.appendingPathComponent("RELL Backup \(dayFormatter.string(from: now))", isDirectory: true)
        var suffix = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = parent.appendingPathComponent(
                "RELL Backup \(dayFormatter.string(from: now)) \(suffix)", isDirectory: true
            )
            suffix += 1
        }
        try writeSnapshot(from: dataDirectory, defaults: defaults, to: destination)
        return destination
    }

    /// Starts a fresh copy of the app once this one has exited, then quits.
    static func relaunch() {
        let path = Bundle.main.bundleURL.path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", path]
        try? process.run()
        NSApp.terminate(nil)
    }
}
