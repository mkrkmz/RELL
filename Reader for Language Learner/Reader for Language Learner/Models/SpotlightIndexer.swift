//
//  SpotlightIndexer.swift
//  Reader for Language Learner
//
//  Core Spotlight integration: saved words and recently read documents are
//  searchable system-wide. Identifiers encode the deep-link target —
//  "word-<uuid>" reveals the card in the Words tab, "doc-<path>" reopens
//  the PDF through the multi-window openWindow(value:) path.
//

import CoreSpotlight
import Foundation

enum SpotlightIndexer {

    static let wordDomain = "savedWords"
    static let documentDomain = "documents"

    private static let wordPrefix = "word-"
    private static let documentPrefix = "doc-"

    // MARK: - Identifiers

    static func identifier(for word: SavedWord) -> String {
        wordPrefix + word.id.uuidString
    }

    static func identifier(forDocumentPath path: String) -> String {
        documentPrefix + path
    }

    /// Decodes a Spotlight identifier back into a deep-link target.
    enum Target {
        case word(UUID)
        case document(URL)
    }

    static func target(from identifier: String) -> Target? {
        if identifier.hasPrefix(wordPrefix),
           let id = UUID(uuidString: String(identifier.dropFirst(wordPrefix.count))) {
            return .word(id)
        }
        if identifier.hasPrefix(documentPrefix) {
            let path = String(identifier.dropFirst(documentPrefix.count))
            guard !path.isEmpty else { return nil }
            return .document(URL(fileURLWithPath: path))
        }
        return nil
    }

    // MARK: - Words

    static func index(_ word: SavedWord) {
        CSSearchableIndex.default().indexSearchableItems([searchableItem(for: word)])
    }

    static func removeWord(id: UUID) {
        CSSearchableIndex.default()
            .deleteSearchableItems(withIdentifiers: [wordPrefix + id.uuidString])
    }

    /// Launch-time sync: rebuilds the word domain so edits, tag changes,
    /// and deletions that bypassed the hooks never leave stale results.
    static func reindexAllWords(_ words: [SavedWord]) {
        let index = CSSearchableIndex.default()
        index.deleteSearchableItems(withDomainIdentifiers: [wordDomain]) { _ in
            index.indexSearchableItems(words.map(searchableItem(for:)))
        }
    }

    private static func searchableItem(for word: SavedWord) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = word.term

        let definition = (word.llmOutputs[ModuleType.definitionEN.rawValue] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        attributes.contentDescription = definition.isEmpty ? word.sentence : definition
        attributes.keywords = [word.term] + word.tags
        if let pdfFilename = word.pdfFilename {
            attributes.containerTitle = pdfFilename
        }

        let item = CSSearchableItem(
            uniqueIdentifier: identifier(for: word),
            domainIdentifier: wordDomain,
            attributeSet: attributes
        )
        item.expirationDate = .distantFuture
        return item
    }

    // MARK: - Documents

    static func indexDocument(at url: URL) {
        let isEPUB = url.pathExtension.lowercased() == "epub"
        let attributes = CSSearchableItemAttributeSet(contentType: isEPUB ? .epub : .pdf)
        attributes.title = url.deletingPathExtension().lastPathComponent
        attributes.contentDescription = isEPUB
            ? String(localized: "Book in your RELL library")
            : String(localized: "PDF in your RELL library")
        attributes.contentURL = url

        let item = CSSearchableItem(
            uniqueIdentifier: identifier(forDocumentPath: url.path),
            domainIdentifier: documentDomain,
            attributeSet: attributes
        )
        item.expirationDate = .distantFuture
        CSSearchableIndex.default().indexSearchableItems([item])
    }

    static func removeDocument(path: String) {
        CSSearchableIndex.default()
            .deleteSearchableItems(withIdentifiers: [documentPrefix + path])
    }
}
