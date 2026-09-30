//
//  PersistenceSafetyTests.swift
//  Reader for Language LearnerTests
//
//  v1.39: an unreadable store file is quarantined instead of overwritten,
//  writes land in order, and daily backups / restore / export round-trip.
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class PersistenceSafetyTests: XCTestCase {
    private static var retained: [AnyObject] = []

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PersistenceSafetyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func makeDefaults() -> UserDefaults {
        let name = "PersistenceSafetyTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: name) }
        return defaults
    }

    private func terms(at url: URL) throws -> [String] {
        try JSONDecoder().decode([SavedWord].self, from: Data(contentsOf: url)).map(\.term)
    }

    // MARK: - Quarantine

    /// The v1.38 bug, reproduced during the v12 review: one torn byte and the
    /// next save replaced the whole vocabulary with the single new word.
    func testUnreadableVocabularyIsSetAsideNotOverwritten() async throws {
        let directory = try makeTempDirectory()
        let url = directory.appendingPathComponent("saved_words.json")
        let seed = SavedWordsStore(fileURL: url)
        Self.retained.append(seed)
        seed.add(SavedWord(term: "alpha"))
        seed.add(SavedWord(term: "beta"))
        var torn = try Data(contentsOf: url)
        torn.removeLast()
        try torn.write(to: url)
        _ = PersistenceRecovery.takePending()

        let reopened = SavedWordsStore(fileURL: url)
        Self.retained.append(reopened)
        XCTAssertTrue(reopened.words.isEmpty)
        reopened.add(SavedWord(term: "gamma"))

        let pending = PersistenceRecovery.takePending()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.originalName, "saved_words.json")
        let quarantined = try XCTUnwrap(pending.first?.url)
        XCTAssertTrue(quarantined.lastPathComponent.hasPrefix("saved_words.corrupt-"))
        XCTAssertEqual(try Data(contentsOf: quarantined), torn, "the unreadable bytes survive untouched")
        XCTAssertEqual(try terms(at: url), ["gamma"])
    }

    func testQuarantineNeverOverwritesAnEarlierQuarantine() async throws {
        let directory = try makeTempDirectory()
        let url = directory.appendingPathComponent("pdf_notes.json")
        let now = Date(timeIntervalSince1970: 1_790_000_000)

        try Data("first".utf8).write(to: url)
        let first = try XCTUnwrap(PersistenceRecovery.quarantine(url, userVisible: false, now: now))
        try Data("second".utf8).write(to: url)
        let second = try XCTUnwrap(PersistenceRecovery.quarantine(url, userVisible: false, now: now))

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "first")
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), "second")
    }

    func testSilentQuarantineIsNotReported() async throws {
        let directory = try makeTempDirectory()
        let url = directory.appendingPathComponent("llm_output_cache.json")
        try Data("{".utf8).write(to: url)
        _ = PersistenceRecovery.takePending()

        let loaded = RELLJSONStore.load([String].self, from: url, storeName: "Test", userVisible: false, defaultValue: [])

        XCTAssertEqual(loaded, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(PersistenceRecovery.takePending().isEmpty)
    }

    func testMissingOrEmptyFileIsNotQuarantined() async throws {
        let directory = try makeTempDirectory()
        let url = directory.appendingPathComponent("epub_notes.json")
        _ = PersistenceRecovery.takePending()

        XCTAssertEqual(RELLJSONStore.load([String].self, from: url, storeName: "Test", defaultValue: ["d"]), ["d"])
        try Data().write(to: url)
        XCTAssertEqual(RELLJSONStore.load([String].self, from: url, storeName: "Test", defaultValue: ["d"]), ["d"])

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(PersistenceRecovery.takePending().isEmpty)
    }

    // MARK: - Write ordering

    /// A debounced snapshot still queued when `flush()` writes a newer one
    /// must not land afterwards and win (the termination-flush race).
    func testFlushedSnapshotIsNotReplacedByAnOlderInFlightWrite() async throws {
        let directory = try makeTempDirectory()
        let url = directory.appendingPathComponent("order.json")
        let writer = DebouncedFileWriter(fileURL: url, storeName: "OrderTest", debounce: 0.01)
        Self.retained.append(writer)

        writer.suspendIOForTesting()
        writer.schedule { Data("older".utf8) }
        try await Task.sleep(for: .milliseconds(100))  // debounce fired; "older" waits on ioQueue
        writer.schedule { Data("newer".utf8) }
        writer.flush()
        XCTAssertEqual(try Data(contentsOf: url), Data("newer".utf8))

        writer.resumeIOForTesting()
        try await Task.sleep(for: .milliseconds(300))  // the queued write runs now

        XCTAssertEqual(try Data(contentsOf: url), Data("newer".utf8))
    }

    func testSuspendedWritesAreDropped() async throws {
        let directory = try makeTempDirectory()
        let url = directory.appendingPathComponent("suspended.json")
        let writer = DebouncedFileWriter(fileURL: url, storeName: "SuspendTest", debounce: 0)
        Self.retained.append(writer)
        writer.schedule { Data("before".utf8) }

        PersistenceCoordinator.discardPendingWrites()
        defer { PersistenceCoordinator.resumeWritesForTesting() }
        writer.schedule { Data("after".utf8) }
        writer.flush()

        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "before")
    }

    // MARK: - Daily backups

    func testDailyBackupCopiesDataOncePerDay() async throws {
        let directory = try makeTempDirectory()
        let defaults = makeDefaults()
        try Data("[]".utf8).write(to: directory.appendingPathComponent("saved_words.json"))
        try Data("[1]".utf8).write(to: directory.appendingPathComponent("pdf_notes.json"))
        try Data("cache".utf8).write(to: directory.appendingPathComponent("llm_output_cache.json"))
        defaults.set(Data("marks".utf8), forKey: PersistenceBackup.pdfBookmarksDefaultsKey)
        let now = Date(timeIntervalSince1970: 1_790_000_000)

        let folder = try XCTUnwrap(PersistenceBackup.runDailyIfNeeded(dataDirectory: directory, defaults: defaults, now: now))
        let copied = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        XCTAssertEqual(copied, ["pdf_bookmarks.json", "pdf_notes.json", "saved_words.json"])

        XCTAssertNil(PersistenceBackup.runDailyIfNeeded(
            dataDirectory: directory, defaults: defaults, now: now.addingTimeInterval(3600)
        ))
        XCTAssertEqual(PersistenceBackup.dailyBackups(dataDirectory: directory).count, 1)
    }

    func testDailyBackupsKeepTheNewestSeven() async throws {
        let directory = try makeTempDirectory()
        let defaults = makeDefaults()
        try Data("[]".utf8).write(to: directory.appendingPathComponent("saved_words.json"))
        let start = Date(timeIntervalSince1970: 1_790_000_000)

        for day in 0..<10 {
            PersistenceBackup.runDailyIfNeeded(
                dataDirectory: directory, defaults: defaults,
                now: start.addingTimeInterval(Double(day) * 86_400)
            )
        }

        let backups = PersistenceBackup.dailyBackups(dataDirectory: directory)
        XCTAssertEqual(backups.count, 7)
        XCTAssertEqual(
            Calendar.current.startOfDay(for: backups[0].date),
            Calendar.current.startOfDay(for: start.addingTimeInterval(9 * 86_400)),
            "newest first"
        )
    }

    // MARK: - Restore / export

    func testRestoreReplacesDataAndKeepsASafetyCopy() async throws {
        let live = try makeTempDirectory()
        let backup = try makeTempDirectory()
        let defaults = makeDefaults()
        try Data("\"live\"".utf8).write(to: live.appendingPathComponent("saved_words.json"))
        try Data("\"live notes\"".utf8).write(to: live.appendingPathComponent("pdf_notes.json"))
        defaults.set(Data("live marks".utf8), forKey: PersistenceBackup.pdfBookmarksDefaultsKey)
        try Data("\"restored\"".utf8).write(to: backup.appendingPathComponent("saved_words.json"))
        try Data("backup marks".utf8).write(to: backup.appendingPathComponent("pdf_bookmarks.json"))

        defer { PersistenceCoordinator.resumeWritesForTesting() }
        try PersistenceBackup.restore(from: backup, dataDirectory: live, defaults: defaults)

        XCTAssertTrue(PersistenceCoordinator.isSuspended)
        XCTAssertEqual(try String(contentsOf: live.appendingPathComponent("saved_words.json"), encoding: .utf8), "\"restored\"")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: live.appendingPathComponent("pdf_notes.json").path),
            "a file the backup didn't have was empty then"
        )
        XCTAssertEqual(defaults.data(forKey: PersistenceBackup.pdfBookmarksDefaultsKey), Data("backup marks".utf8))

        let backupsRoot = live.appendingPathComponent(PersistenceBackup.backupsFolderName)
        let safety = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(at: backupsRoot, includingPropertiesForKeys: nil)
                .first { $0.lastPathComponent.hasPrefix("before-restore-") }
        )
        XCTAssertEqual(try String(contentsOf: safety.appendingPathComponent("saved_words.json"), encoding: .utf8), "\"live\"")
        XCTAssertEqual(try Data(contentsOf: safety.appendingPathComponent("pdf_bookmarks.json")), Data("live marks".utf8))
        XCTAssertTrue(PersistenceBackup.dailyBackups(dataDirectory: live).isEmpty, "a safety copy isn't a daily backup")
    }

    func testExportWritesARestorableFolder() async throws {
        let live = try makeTempDirectory()
        let parent = try makeTempDirectory()
        let defaults = makeDefaults()
        try Data("[]".utf8).write(to: live.appendingPathComponent("saved_words.json"))
        let now = Date(timeIntervalSince1970: 1_790_000_000)

        let first = try PersistenceBackup.export(to: parent, dataDirectory: live, defaults: defaults, now: now)
        let second = try PersistenceBackup.export(to: parent, dataDirectory: live, defaults: defaults, now: now)

        XCTAssertTrue(first.lastPathComponent.hasPrefix("RELL Backup "))
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(PersistenceBackup.isBackupFolder(first))
        XCTAssertFalse(PersistenceBackup.isBackupFolder(parent))
    }

    // MARK: - Test host isolation (v13 Sprint 5)

    /// The tests run inside the app; the app must not be using the user's
    /// real data folder while they do.
    func testTestHostUsesAThrowawayDataFolder() async throws {
        XCTAssertTrue(RELLProcess.isTestHost)
        let folder = try XCTUnwrap(FileManager.default.rellAppSupportDirectory())
        let real = try XCTUnwrap(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
            .appendingPathComponent("RELL")
        XCTAssertNotEqual(folder.standardizedFileURL, real.standardizedFileURL)
        XCTAssertTrue(folder.path.hasPrefix(FileManager.default.temporaryDirectory.path))
    }
}
