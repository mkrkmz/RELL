//
//  SavedWordsStore.swift
//  Reader for Language Learner
//

import Foundation
import os
import SwiftUI

/// Manages persistence and CRUD for the user's saved vocabulary.
/// Stores data as a JSON file in Application Support.
@MainActor
@Observable
final class SavedWordsStore {

    private(set) var words: [SavedWord] = []
    var saveError: String? = nil

    private let fileURL: URL

    init() {
        guard let appSupport = FileManager.default.rellAppSupportDirectory() else {
            // Fallback to temp directory if Application Support unavailable
            self.fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("saved_words.json")
            self.words = []
            return
        }

        self.fileURL = appSupport.appendingPathComponent("saved_words.json")
        self.words = Self.load(from: fileURL)
    }

    // MARK: - CRUD

    func add(_ word: SavedWord) {
        if words.contains(where: {
            $0.term.lowercased() == word.term.lowercased()
                && $0.pdfFilename == word.pdfFilename
                && $0.pageNumber  == word.pageNumber
                && $0.mode        == word.mode
                && $0.domain      == word.domain
        }) {
            return
        }
        words.insert(word, at: 0)
        save()
    }

    func update(_ word: SavedWord) {
        guard let index = words.firstIndex(where: { $0.id == word.id }) else { return }
        words[index] = word
        save()
    }

    func delete(_ word: SavedWord) {
        words.removeAll { $0.id == word.id }
        save()
    }

    func delete(at offsets: IndexSet) {
        words.remove(atOffsets: offsets)
        save()
    }

    func deleteAll() {
        words.removeAll()
        save()
    }

    func isSaved(term: String, pdfFilename: String?, pageNumber: Int?) -> Bool {
        words.contains {
            $0.term.lowercased() == term.lowercased()
                && $0.pdfFilename == pdfFilename
                && $0.pageNumber == pageNumber
        }
    }

    func remove(term: String, pdfFilename: String?, pageNumber: Int?) {
        words.removeAll {
            $0.term.lowercased() == term.lowercased()
                && $0.pdfFilename == pdfFilename
                && $0.pageNumber == pageNumber
        }
        save()
    }

    // MARK: - Persistence

    private func save() {
        do {
            let data = try JSONEncoder().encode(words)
            try data.write(to: fileURL, options: .atomic)
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }

    private static func load(from url: URL) -> [SavedWord] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([SavedWord].self, from: data)
        } catch {
            AppLogger.persistence.error("SavedWordsStore load failed: \(error.localizedDescription)")
            return []
        }
    }
}

