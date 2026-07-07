//
//  ReadingSessionStoreTests.swift
//  Reader for Language LearnerTests
//
//  Session lifecycle (start/end, short-session discard) and the stats
//  built on top (today/total time, streaks, 7-day breakdown). Historical
//  sessions are seeded by encoding them straight into the store's JSON
//  file — the same path `RecentDocumentStoreTests`'s legacy-decode test
//  uses — so streak math can be tested without sleeping in real time.
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class ReadingSessionStoreTests: XCTestCase {
    private static var retainedStores: [ReadingSessionStore] = []

    // MARK: - Lifecycle

    func testStartSessionMakesItActive() {
        let store = makeStore()
        store.startSession(for: "book.pdf")

        XCTAssertNotNil(store.activeSession)
        XCTAssertEqual(store.activeSession?.pdfFilename, "book.pdf")
        XCTAssertTrue(store.activeSession?.isActive == true)
    }

    func testStartingNewSessionEndsThePreviousOne() {
        let store = makeStore()
        store.startSession(for: "first.pdf")
        store.startSession(for: "second.pdf")

        XCTAssertEqual(store.activeSession?.pdfFilename, "second.pdf")
    }

    func testEndActiveSessionClearsIt() {
        let store = makeStore()
        store.startSession(for: "book.pdf")
        store.endActiveSession()

        XCTAssertNil(store.activeSession)
    }

    func testEndActiveSessionDiscardsSessionsUnderFiveSeconds() {
        let store = makeStore()
        store.startSession(for: "book.pdf")
        store.endActiveSession()

        // A session ended immediately after starting is well under the
        // 5-second persistence threshold.
        XCTAssertTrue(store.sessions.isEmpty)
    }

    func testEndActiveSessionWithNoActiveSessionIsANoOp() {
        let store = makeStore()
        store.endActiveSession()
        XCTAssertNil(store.activeSession)
        XCTAssertTrue(store.sessions.isEmpty)
    }

    // MARK: - Stats (seeded via persisted sessions)

    func testTodayReadingTimeSumsOnlyTodaysSessions() throws {
        let now = Date()
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!

        let store = try makeStore(seeding: [
            session(pdfFilename: "a.pdf", startedAt: now.addingTimeInterval(-120), endedAt: now.addingTimeInterval(-60)),
            session(pdfFilename: "b.pdf", startedAt: yesterday, endedAt: yesterday.addingTimeInterval(600)),
        ])

        XCTAssertEqual(store.todayReadingTime, 60, accuracy: 0.5)
        XCTAssertEqual(store.totalReadingTime, 660, accuracy: 0.5)
    }

    func testTotalTimeForFilenameFiltersByDocument() throws {
        let now = Date()
        let store = try makeStore(seeding: [
            session(pdfFilename: "a.pdf", startedAt: now.addingTimeInterval(-100), endedAt: now.addingTimeInterval(-50)),
            session(pdfFilename: "b.pdf", startedAt: now.addingTimeInterval(-100), endedAt: now.addingTimeInterval(-20)),
        ])

        XCTAssertEqual(store.totalTime(for: "a.pdf"), 50, accuracy: 0.5)
        XCTAssertEqual(store.totalTime(for: "b.pdf"), 80, accuracy: 0.5)
        XCTAssertEqual(store.totalTime(for: "missing.pdf"), 0)
    }

    func testUniqueDocumentsReadCountsDistinctFilenames() throws {
        let now = Date()
        let store = try makeStore(seeding: [
            session(pdfFilename: "a.pdf", startedAt: now, endedAt: now.addingTimeInterval(10)),
            session(pdfFilename: "a.pdf", startedAt: now, endedAt: now.addingTimeInterval(10)),
            session(pdfFilename: "b.pdf", startedAt: now, endedAt: now.addingTimeInterval(10)),
        ])

        XCTAssertEqual(store.uniqueDocumentsRead, 2)
    }

    func testCurrentStreakCountsConsecutiveDaysEndingToday() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let sessions = (0..<3).map { offset -> ReadingSession in
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            return session(pdfFilename: "book.pdf", startedAt: day, endedAt: day.addingTimeInterval(60))
        }
        let store = try makeStore(seeding: sessions)

        XCTAssertEqual(store.currentStreak, 3)
    }

    func testCurrentStreakIsZeroWhenGapBeforeYesterday() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: today)!
        let store = try makeStore(seeding: [
            session(pdfFilename: "book.pdf", startedAt: threeDaysAgo, endedAt: threeDaysAgo.addingTimeInterval(60)),
        ])

        XCTAssertEqual(store.currentStreak, 0)
    }

    func testLongestStreakFindsBestRunAcrossGaps() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        // Two separate 2-day runs, 10 days apart — longest streak is 2.
        let recentRun = (0..<2).map { offset -> ReadingSession in
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            return session(pdfFilename: "book.pdf", startedAt: day, endedAt: day.addingTimeInterval(60))
        }
        let oldRun = (10..<13).map { offset -> ReadingSession in
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            return session(pdfFilename: "book.pdf", startedAt: day, endedAt: day.addingTimeInterval(60))
        }
        let store = try makeStore(seeding: recentRun + oldRun)

        XCTAssertEqual(store.longestStreak, 3)
    }

    func testLast7DaysHasSevenEntriesEndingToday() throws {
        let store = try makeStore(seeding: [])
        let days = store.last7Days

        XCTAssertEqual(days.count, 7)
        let calendar = Calendar.current
        XCTAssertTrue(calendar.isDateInToday(days.last!.day))
    }

    // MARK: - Helpers

    private func session(pdfFilename: String, startedAt: Date, endedAt: Date?) -> ReadingSession {
        var data = ReadingSession(pdfFilename: pdfFilename)
        // ReadingSession's memberwise fields are all `let` except endedAt,
        // and its only initializer stamps `startedAt = Date()` — re-encode
        // through JSON to land on the exact historical dates we need.
        struct Patch: Codable {
            let id: UUID
            let pdfFilename: String
            let startedAt: Date
            var endedAt: Date?
        }
        let patched = Patch(id: data.id, pdfFilename: data.pdfFilename, startedAt: startedAt, endedAt: endedAt)
        data = try! JSONDecoder().decode(ReadingSession.self, from: try! JSONEncoder().encode(patched))
        return data
    }

    private func makeStore() -> ReadingSessionStore {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let store = ReadingSessionStore(fileURL: fileURL)
        Self.retainedStores.append(store)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: fileURL)
        }
        return store
    }

    private func makeStore(seeding sessions: [ReadingSession]) throws -> ReadingSessionStore {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        try JSONEncoder().encode(sessions).write(to: fileURL)
        let store = ReadingSessionStore(fileURL: fileURL)
        Self.retainedStores.append(store)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: fileURL)
        }
        return store
    }
}
