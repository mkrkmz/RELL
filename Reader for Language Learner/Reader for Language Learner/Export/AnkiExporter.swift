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

/// Output flavors for bulk export. Raw values are stable — they back
/// `@AppStorage("bulkExportFormat")`.
enum ExportFormat: String, CaseIterable, Identifiable {
    case ankiTSV = "Anki TSV"
    case csv = "CSV"
    case quizletTSV = "Quizlet"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .ankiTSV, .quizletTSV: return "tsv"
        case .csv: return "csv"
        }
    }

    var contentType: UTType {
        switch self {
        case .ankiTSV, .quizletTSV: return .tabSeparatedText
        case .csv: return .commaSeparatedText
        }
    }

    /// One-line hint shown under the format picker.
    var localizedHint: String {
        switch self {
        case .ankiTSV:
            return String(localized: "Anki import file with HTML formatting, tags, and source.")
        case .csv:
            return String(localized: "Plain-text spreadsheet: Front, Back, Tags, Source columns.")
        case .quizletTSV:
            return String(localized: "Two columns (term and definition) for Quizlet's import box.")
        }
    }
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
        tags: String,
        extraTags: [String] = []
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
        // Anki separates tags by spaces, so each tag must be a single token;
        // collapse any internal whitespace in per-word tags to underscores.
        let baseTokens = tags
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
        let extraTokens = extraTags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines)
                     .replacingOccurrences(of: " ", with: "_") }
            .filter { !$0.isEmpty }
        var seenTags = Set<String>()
        let normalizedTags = (baseTokens + extraTokens)
            .filter { seenTags.insert($0.lowercased()).inserted }
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

    // MARK: - Format Dispatch

    static func document(from notes: [AnkiNoteDraft], format: ExportFormat) -> String {
        switch format {
        case .ankiTSV:    return tsvDocument(from: notes)
        case .csv:        return csvDocument(from: notes)
        case .quizletTSV: return quizletDocument(from: notes)
        }
    }

    /// RFC 4180-style CSV with a header row. The back field is converted
    /// from Anki HTML to plain text (real newlines survive inside quotes).
    static func csvDocument(from notes: [AnkiNoteDraft]) -> String {
        guard !notes.isEmpty else { return "" }
        let header = "Front,Back,Tags,Source"
        let rows = notes.map { note in
            [note.front, plainText(fromAnkiHTML: note.back), note.tags, note.source]
                .map(escapeCSV)
                .joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    /// Quizlet's import box wants exactly `term<TAB>definition` per line —
    /// no header, no extra columns, no embedded tabs or newlines.
    static func quizletDocument(from notes: [AnkiNoteDraft]) -> String {
        guard !notes.isEmpty else { return "" }
        let rows = notes.map { note in
            let term = note.front.replacingOccurrences(of: "\t", with: " ")
            let definition = plainText(fromAnkiHTML: note.back)
                .replacingOccurrences(of: "\n", with: " · ")
                .replacingOccurrences(of: "\t", with: " ")
            return "\(term)\t\(definition)"
        }
        return rows.joined(separator: "\n") + "\n"
    }

    /// Converts the note back's Anki HTML (built by `buildNote`) to plain
    /// text: `<br>` → newline, `<b>`/`<i>` and any other tags stripped.
    static func plainText(fromAnkiHTML html: String) -> String {
        html
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Save

    /// Opens NSSavePanel and writes the export file for the given format.
    @MainActor
    static func save(content: String, format: ExportFormat) async -> Bool {
        let panel = NSSavePanel()
        panel.title = "Export Cards"
        panel.nameFieldStringValue = defaultFilename(for: format)
        panel.allowedContentTypes = [format.contentType]
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
            AppLogger.export.error("Export save failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Legacy entry point used by the inspector's quick export.
    @MainActor
    static func saveTSV(content: String) async -> Bool {
        await save(content: content, format: .ankiTSV)
    }

    // MARK: - Helpers

    private static func defaultFilename(for format: ExportFormat) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "RELL_export_\(formatter.string(from: Date())).\(format.fileExtension)"
    }

    /// Quotes a CSV field when it contains a comma, quote, or newline.
    private static func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
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

