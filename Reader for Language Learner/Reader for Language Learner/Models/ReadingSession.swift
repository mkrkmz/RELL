//
//  ReadingSession.swift
//  Reader for Language Learner
//
//  A single reading session: opening a document and reading until navigation away.
//

import Foundation

struct ReadingSession: Codable, Identifiable {
    let id: UUID
    let pdfFilename: String
    let startedAt: Date
    var endedAt: Date?

    init(pdfFilename: String) {
        self.id          = UUID()
        self.pdfFilename = pdfFilename
        self.startedAt   = Date()
    }

    var durationSeconds: Double {
        (endedAt ?? Date()).timeIntervalSince(startedAt)
    }

    var isActive: Bool { endedAt == nil }
}
