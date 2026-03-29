//
//  SavedWord.swift
//  Reader for Language Learner
//
//  Created by Codex on 15.02.2026.
//

import Foundation

/// A single word or phrase saved by the user during reading.
struct SavedWord: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var term: String
    var sentence: String
    var pdfFilename: String?
    var pageNumber: Int?
    var mode: String          // ExplainMode.rawValue
    var domain: String        // DomainPreference.rawValue
    var notes: String
    /// Snapshot of LLM outputs at save time. Key = ModuleType.rawValue.
    var llmOutputs: [String: String]
    var savedAt: Date

    init(
        id: UUID = UUID(),
        term: String,
        sentence: String = "",
        pdfFilename: String? = nil,
        pageNumber: Int? = nil,
        mode: String = ExplainMode.word.rawValue,
        domain: String = DomainPreference.general.rawValue,
        notes: String = "",
        llmOutputs: [String: String] = [:],
        savedAt: Date = Date()
    ) {
        self.id = id
        self.term = term
        self.sentence = sentence
        self.pdfFilename = pdfFilename
        self.pageNumber = pageNumber
        self.mode = mode
        self.domain = domain
        self.notes = notes
        self.llmOutputs = llmOutputs
        self.savedAt = savedAt
    }
}
