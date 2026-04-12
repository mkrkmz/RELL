//
//  ReadingSessionStore.swift
//  Reader for Language Learner
//
//  Tracks and persists reading sessions. Provides aggregated stats for the Stats panel.
//

import Foundation
import os

@MainActor
@Observable
final class ReadingSessionStore {

    // MARK: - State

    private(set) var sessions: [ReadingSession] = []
    private(set) var activeSession: ReadingSession?

    private let fileURL: URL

    // MARK: - Init

    init() {
        guard let dir = FileManager.default.rellAppSupportDirectory() else {
            self.fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("reading_sessions.json")
            self.sessions = []
            return
        }
        self.fileURL = dir.appendingPathComponent("reading_sessions.json")
        self.sessions = Self.load(from: fileURL)
    }

    // MARK: - Session Lifecycle

    /// Call when the user opens (or switches to) a PDF document.
    func startSession(for filename: String) {
        endActiveSession()
        activeSession = ReadingSession(pdfFilename: filename)
    }

    /// Call when the user closes or switches away from a document.
    func endActiveSession() {
        guard var session = activeSession else { return }
        session.endedAt = Date()
        activeSession = nil
        // Only persist sessions longer than 5 seconds
        guard session.durationSeconds >= 5 else { return }
        sessions.insert(session, at: 0)
        // Cap to last 500 sessions
        if sessions.count > 500 { sessions = Array(sessions.prefix(500)) }
        save()
    }

    // MARK: - Stats

    /// Live today reading time (includes active session).
    var todayReadingTime: Double {
        let dayStart = Calendar.current.startOfDay(for: Date())
        let completed = sessions
            .filter { $0.startedAt >= dayStart }
            .reduce(0.0) { $0 + $1.durationSeconds }
        let live = activeSession.map { $0.durationSeconds } ?? 0
        return completed + live
    }

    /// All-time total reading time.
    var totalReadingTime: Double {
        sessions.reduce(0.0) { $0 + $1.durationSeconds }
            + (activeSession.map { $0.durationSeconds } ?? 0)
    }

    /// Number of unique PDFs with at least one completed session.
    var uniqueDocumentsRead: Int {
        Set(sessions.map { $0.pdfFilename }).count
    }

    /// Total reading time for a specific PDF (completed sessions only).
    func totalTime(for filename: String) -> Double {
        sessions
            .filter { $0.pdfFilename == filename }
            .reduce(0.0) { $0 + $1.durationSeconds }
    }

    // MARK: - Streak

    /// Consecutive days (ending today or yesterday) with at least one reading session.
    var currentStreak: Int {
        let cal = Calendar.current
        var checkDate = cal.startOfDay(for: Date())

        let todayHasSession = sessions.contains { cal.isDate($0.startedAt, inSameDayAs: Date()) }
        if !todayHasSession {
            guard let yesterday = cal.date(byAdding: .day, value: -1, to: checkDate) else { return 0 }
            let yesterdayHasSession = sessions.contains { cal.isDate($0.startedAt, inSameDayAs: yesterday) }
            guard yesterdayHasSession else { return 0 }
            checkDate = yesterday
        }

        var streak = 0
        while true {
            guard let dayEnd = cal.date(byAdding: .day, value: 1, to: checkDate) else { break }
            let hasSession = sessions.contains { $0.startedAt >= checkDate && $0.startedAt < dayEnd }
            guard hasSession else { break }
            streak += 1
            guard let prevDay = cal.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = prevDay
        }
        return streak
    }

    /// All-time longest reading streak (in days).
    var longestStreak: Int {
        guard !sessions.isEmpty else { return 0 }
        let cal = Calendar.current
        let days = Set(sessions.map { cal.startOfDay(for: $0.startedAt) }).sorted()
        var best = 1, current = 1
        for i in 1..<days.count {
            if let expected = cal.date(byAdding: .day, value: 1, to: days[i - 1]),
               cal.isDate(expected, inSameDayAs: days[i]) {
                current += 1
                best = max(best, current)
            } else {
                current = 1
            }
        }
        return best
    }

    // MARK: - 7-Day Breakdown (for bar chart)

    struct DayStats: Identifiable {
        let id: Date
        let day: Date
        let seconds: Double
        let label: String   // "Mon", "Tue", …

        init(day: Date, seconds: Double) {
            self.id      = day
            self.day     = day
            self.seconds = seconds
            let fmt = DateFormatter()
            fmt.dateFormat = "EEE"
            self.label = fmt.string(from: day)
        }
    }

    var last7Days: [DayStats] {
        let cal = Calendar.current
        return (0..<7).compactMap { offset -> DayStats? in
            guard let day  = cal.date(byAdding: .day, value: -(6 - offset), to: cal.startOfDay(for: Date())),
                  let next = cal.date(byAdding: .day, value: 1, to: day)
            else { return nil }
            let total = sessions
                .filter { $0.startedAt >= day && $0.startedAt < next }
                .reduce(0.0) { $0 + $1.durationSeconds }
            return DayStats(day: day, seconds: total)
        }
    }

    // MARK: - Persistence

    private func save() {
        do {
            let data = try JSONEncoder().encode(sessions)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            AppLogger.persistence.error("ReadingSessionStore save failed: \(error.localizedDescription)")
        }
    }

    private static func load(from url: URL) -> [ReadingSession] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([ReadingSession].self, from: data)
        } catch {
            AppLogger.persistence.error("ReadingSessionStore load failed: \(error.localizedDescription)")
            return []
        }
    }
}
