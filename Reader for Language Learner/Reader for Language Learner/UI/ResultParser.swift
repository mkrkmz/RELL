//
//  ResultParser.swift
//  Reader for Language Learner
//
//  Created by Codex on 11.02.2026.
//

import Foundation

// MARK: - CollocationEntry (new markdown format)

/// A single collocation item parsed from the new markdown-formatted LLM output.
struct CollocationEntry: Identifiable, Hashable {
    let id = UUID()
    let number: Int
    let collocation: String       // e.g. "presuppose the existence of"
    let meaning: String           // native-language meaning
    let example: String           // target-language example sentence
    let translationNative: String // native-language translation of the example
}

struct ParsedSection: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let body: String
}

/// A single parsed `LABEL: value` row from usage-notes output.
struct UsageNoteRow: Hashable {
    let label: String
    let value: String
}

/// Memoizes parsed LLM output so result views don't re-run the line-scanning
/// parsers on every SwiftUI render. Keyed by the raw content string; entries
/// are tiny and the cache holds only a handful of recent results.
@MainActor
enum ParsedResultCache {
    private static var collocations = LRUCache<String, [CollocationEntry]>(capacity: 16)
    private static var usageNotes = LRUCache<String, [UsageNoteRow]>(capacity: 16)

    static func collocationEntries(for content: String) -> [CollocationEntry] {
        if let cached = collocations.get(content) { return cached }
        let parsed = ResultParser.parseCollocationEntries(content)
        collocations.set(content, parsed)
        return parsed
    }

    static func usageNoteRows(for content: String) -> [UsageNoteRow] {
        if let cached = usageNotes.get(content) { return cached }
        let parsed = ResultParser.parseUsageNoteRows(content)
        usageNotes.set(content, parsed)
        return parsed
    }
}

enum ResultParser {
    static func parse(_ text: String, module: ModuleType) -> [ParsedSection] {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return [] }

        // All modules now produce plain text — return as a single section.
        return [ParsedSection(title: module.title, body: cleaned)]
    }

    // MARK: - Usage Notes Parser

    /// Parses `LABEL: value` lines (FREQ, REG, CONFUSE, CAUTION…).
    static func parseUsageNoteRows(_ text: String) -> [UsageNoteRow] {
        text
            .components(separatedBy: .newlines)
            .compactMap { raw in
                let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else { return nil }
                guard let colon = line.firstIndex(of: ":") else { return nil }
                let label = String(line[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
                let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !label.isEmpty, !value.isEmpty else { return nil }
                return UsageNoteRow(label: label, value: value)
            }
    }

    // MARK: - Collocation Parser (markdown format)

    /// Parses collocation output produced by the markdown prompt format:
    /// ```
    /// 1. **collocation:** meaning
    ///    - *Example:* "example"
    ///    - *Translation:* "translation"
    /// ```
    /// Bullet matching also accepts the legacy Turkish labels
    /// ("Örnek Cümle" / "Türkçe Çeviri") so cached pre-v1.23 outputs and
    /// occasional model drift still parse.
    static func parseCollocationEntries(_ text: String) -> [CollocationEntry] {
        var entries: [CollocationEntry] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)

            if let (number, collocation, meaning) = parseCollocationHeader(line) {
                var example = ""
                var translationNative = ""

                var j = i + 1
                while j < lines.count {
                    let bullet = lines[j].trimmingCharacters(in: .whitespacesAndNewlines)
                    if bullet.isEmpty { j += 1; continue }
                    // Stop when the next numbered item begins
                    if bullet.range(of: #"^\d+\."#, options: .regularExpression) != nil { break }

                    let lower = bullet.lowercased()
                    if lower.contains("örnek") || lower.contains("example") {
                        example = extractBulletValue(bullet)
                    } else if lower.contains("çeviri") || lower.contains("translation") {
                        translationNative = extractBulletValue(bullet)
                    }
                    j += 1
                }

                entries.append(CollocationEntry(
                    number: number,
                    collocation: collocation,
                    meaning: meaning,
                    example: example,
                    translationNative: translationNative
                ))
                i = j
            } else {
                i += 1
            }
        }

        return entries
    }

    /// Parses a header line such as `1. **collocation:** meaning`
    /// Handles variations: bold/no-bold, colon inside/outside markers.
    private static func parseCollocationHeader(_ line: String) -> (Int, String, String)? {
        // Must start with a digit followed by a period
        guard line.range(of: #"^\d+\."#, options: .regularExpression) != nil else { return nil }

        // Extract the number
        guard let dotIdx = line.firstIndex(of: "."),
              let number = Int(String(line[..<dotIdx])) else { return nil }

        // Everything after "N. "
        var rest = String(line[line.index(after: dotIdx)...])
            .trimmingCharacters(in: .whitespaces)

        // Strip leading bold markers if present
        if rest.hasPrefix("**") { rest = String(rest.dropFirst(2)) }

        // Find the first colon — separates collocation from meaning
        guard let colonIdx = rest.firstIndex(of: ":") else { return nil }

        let rawCollocation = String(rest[..<colonIdx])
            .trimmingCharacters(in: CharacterSet(charactersIn: "* "))
        let rawMeaning = String(rest[rest.index(after: colonIdx)...])
            .trimmingCharacters(in: CharacterSet(charactersIn: "* "))

        guard !rawCollocation.isEmpty, !rawMeaning.isEmpty else { return nil }
        return (number, rawCollocation, rawMeaning)
    }

    /// Extracts the value from a bullet line like `- *Example:* "value here"`.
    private static func extractBulletValue(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespaces)
        // Strip leading bullet/italic markers
        while text.hasPrefix("-") || text.hasPrefix("*") || text.hasPrefix(" ") {
            text = String(text.dropFirst())
        }
        // Take everything after the first colon
        if let colonRange = text.range(of: ":") {
            text = String(text[text.index(after: colonRange.lowerBound)...])
        }
        // Strip surrounding markers and quotes
        return text.trimmingCharacters(in: CharacterSet(charactersIn: "* \""))
    }
}
