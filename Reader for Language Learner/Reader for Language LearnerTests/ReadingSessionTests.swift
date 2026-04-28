//
//  ReadingSessionTests.swift
//  Reader for Language LearnerTests
//

import XCTest
@testable import Reader_for_Language_Learner

final class ReadingSessionTests: XCTestCase {
    private static var retainedStores: [ReadingSessionStore] = []

    func testNewSessionIsActive() {
        let session = ReadingSession(pdfFilename: "test.pdf")
        XCTAssertTrue(session.isActive)
        XCTAssertNil(session.endedAt)
        XCTAssertEqual(session.pdfFilename, "test.pdf")
    }

    func testEndedSessionIsNotActive() {
        var session = ReadingSession(pdfFilename: "test.pdf")
        session.endedAt = Date()
        XCTAssertFalse(session.isActive)
    }

    func testDurationForActiveSession() {
        let session = ReadingSession(pdfFilename: "test.pdf")
        // Active session duration should be >= 0
        XCTAssertGreaterThanOrEqual(session.durationSeconds, 0)
    }

    func testDurationForEndedSession() {
        var session = ReadingSession(pdfFilename: "test.pdf")
        // Simulate 10 seconds of reading
        session.endedAt = session.startedAt.addingTimeInterval(10)
        XCTAssertEqual(session.durationSeconds, 10, accuracy: 0.01)
    }

    func testCodableRoundTrip() throws {
        var session = ReadingSession(pdfFilename: "book.pdf")
        session.endedAt = session.startedAt.addingTimeInterval(60)

        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(ReadingSession.self, from: data)

        XCTAssertEqual(decoded.id, session.id)
        XCTAssertEqual(decoded.pdfFilename, "book.pdf")
        XCTAssertEqual(decoded.durationSeconds, 60, accuracy: 0.01)
        XCTAssertFalse(decoded.isActive)
    }

    @MainActor
    func testStoreIgnoresEmptyPersistenceFile() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        try Data().write(to: fileURL)

        let store = ReadingSessionStore(fileURL: fileURL)
        Self.retainedStores.append(store)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: fileURL)
        }

        XCTAssertTrue(store.sessions.isEmpty)
    }
}
