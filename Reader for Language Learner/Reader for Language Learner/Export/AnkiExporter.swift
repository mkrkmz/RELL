//
//  AnkiExporter.swift
//  Reader for Language Learner
//
//  Created by Codex on 13.02.2026.
//

import AppKit
import Foundation
import os
import UniformTypeIdentifiers

/// Holds the assembled data for one Anki note before serialization.
struct AnkiNoteDraft {
    let front: String
    let back: String
    let tags: String
    let source: String
}

enum AnkiExporter {

    // MARK: - Build Note

    /// Assembles an Anki note draft from the user's selection and module outputs.
    static func buildNote(
        selectedText: String,
        mode: ExplainMode,
        domain: DomainPreference,
        selectedModules: Set<ModuleType>,
        outputs: [ModuleType: String],
        includeSource: Bool,
        pdfFilename: String?,
        pageNumber: Int?,
        contextSentence: String? = nil,
        tags: String
    ) -> AnkiNoteDraft {
        // ── Front ──
        var front = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if domain != .general {
            front += " [\(domain.rawValue)]"
        }

        // ── Back ──
        var backParts: [String] = []
        
        // Context Sentence (if present)
        if let context = contextSentence, !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            backParts.append("<b>Context:</b> \(context)")
        }

        // Ordered list of modules matching the canonical display order.
        let orderedModules: [ModuleType] = [
            .definitionEN, .meaningTR, .collocations,
            .examplesEN, .pronunciationEN, .etymologyEN, .mnemonicEN,
            .synonymsEN, .wordFamilyEN, .usageNotesEN
        ]

        for module in orderedModules {
            guard selectedModules.contains(module),
                  let output = outputs[module],
                  !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            let cleaned = sanitize(output)
            backParts.append("<b>[\(module.title)]</b><br>\(cleaned)")
        }

        let back = backParts.joined(separator: "<br><br>")

        // ── Source ──
        var source = ""
        if includeSource, let filename = pdfFilename {
            source = filename
            if let page = pageNumber {
                source += " (p. \(page))"
            }
        }

        // ── Tags ──
        let normalizedTags = tags
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return AnkiNoteDraft(
            front: front,
            back: back,
            tags: normalizedTags,
            source: source
        )
    }

    // MARK: - TSV Serialization

    /// Produces a single TSV row: Front\tBack\tTags\tSource
    static func tsvRow(from note: AnkiNoteDraft) -> String {
        let fields = [note.front, note.back, note.tags, note.source]
        return fields
            .map { escapeTSV($0) }
            .joined(separator: "\t")
    }

    /// Wraps the row with a header comment for Anki import.
    static func tsvDocument(from note: AnkiNoteDraft) -> String {
        let header = "#separator:tab\n#html:true\n#columns:Front\tBack\tTags\tSource"
        let row = tsvRow(from: note)
        return header + "\n" + row + "\n"
    }

    /// Multi-row TSV document for bulk export.
    static func tsvDocument(from notes: [AnkiNoteDraft]) -> String {
        guard !notes.isEmpty else { return "" }
        let header = "#separator:tab\n#html:true\n#columns:Front\tBack\tTags\tSource"
        let rows = notes.map { tsvRow(from: $0) }.joined(separator: "\n")
        return header + "\n" + rows + "\n"
    }

    // MARK: - Save

    /// Opens NSSavePanel and writes the TSV file.
    @MainActor
    static func saveTSV(content: String) async -> Bool {
        let panel = NSSavePanel()
        panel.title = "Export Anki Cards"
        panel.nameFieldStringValue = defaultFilename()
        panel.allowedContentTypes = [.tabSeparatedText]
        panel.canCreateDirectories = true

        let response: NSApplication.ModalResponse
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            response = await panel.beginSheetModal(for: window)
        } else {
            response = panel.runModal()
        }

        guard response == .OK, let url = panel.url else { return false }

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            AppLogger.export.error("Anki export save failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Helpers

    private static func defaultFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "RELL_anki_\(formatter.string(from: Date())).tsv"
    }

    /// Escapes a field value for TSV: replace tabs with spaces, newlines with <br>.
    private static func escapeTSV(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\r\n", with: "<br>")
            .replacingOccurrences(of: "\r", with: "<br>")
            .replacingOccurrences(of: "\n", with: "<br>")
    }

    /// Removes markdown code fences, converts inline markdown to HTML, and
    /// replaces newlines with `<br>` for Anki's HTML renderer.
    private static func sanitize(_ text: String) -> String {
        let cleaned = MarkdownUtils.sanitizeLLMOutput(text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Convert markdown → HTML before newline substitution so patterns stay on one line
        let htmlified = convertMarkdownToHTML(cleaned)
        return htmlified
            .replacingOccurrences(of: "\r\n", with: "<br>")
            .replacingOccurrences(of: "\r",   with: "<br>")
            .replacingOccurrences(of: "\n",   with: "<br>")
    }

    /// Converts inline markdown bold/italic to HTML tags.
    /// Order: bold first (to avoid partial matches with italic's single `*`).
    private static func convertMarkdownToHTML(_ text: String) -> String {
        var result = text

        // **bold** → <b>bold</b>
        if let regex = try? NSRegularExpression(pattern: #"\*\*(.+?)\*\*"#) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result, range: range, withTemplate: "<b>$1</b>"
            )
        }

        // *italic* → <i>italic</i>  (single *, not already part of **)
        if let regex = try? NSRegularExpression(pattern: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result, range: range, withTemplate: "<i>$1</i>"
            )
        }

        return result
    }
}

