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
    let collocation: String   // e.g. "presuppose the existence of"
    let meaning: String       // native-language meaning
    let exampleEN: String     // English example sentence
    let translationTR: String // Native translation of example
}

struct ParsedSection: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let body: String
}

enum ResultParser {
    static func parse(_ text: String, module: ModuleType) -> [ParsedSection] {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return [] }

        // All modules now produce plain text — return as a single section.
        return [ParsedSection(title: module.title, body: cleaned)]
    }

    // MARK: - Collocation Parser (markdown format)

    /// Parses collocation output produced by the new markdown prompt format:
    /// ```
    /// 1. **collocation:** meaning
    ///    - *Örnek Cümle:* "example"
    ///    - *Türkçe Çeviri:* "translation"
    /// ```
    static func parseCollocationEntries(_ text: String) -> [CollocationEntry] {
        var entries: [CollocationEntry] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)

            if let (number, collocation, meaning) = parseCollocationHeader(line) {
                var exampleEN = ""
                var translationTR = ""

                var j = i + 1
                while j < lines.count {
                    let bullet = lines[j].trimmingCharacters(in: .whitespacesAndNewlines)
                    if bullet.isEmpty { j += 1; continue }
                    // Stop when the next numbered item begins
                    if bullet.range(of: #"^\d+\."#, options: .regularExpression) != nil { break }

                    let lower = bullet.lowercased()
                    if lower.contains("örnek") || lower.contains("example") {
                        exampleEN = extractBulletValue(bullet)
                    } else if lower.contains("çeviri") || lower.contains("translation") {
                        translationTR = extractBulletValue(bullet)
                    }
                    j += 1
                }

                entries.append(CollocationEntry(
                    number: number,
                    collocation: collocation,
                    meaning: meaning,
                    exampleEN: exampleEN,
                    translationTR: translationTR
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

    /// Extracts the value from a bullet line like `- *Örnek Cümle:* "value here"`.
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
