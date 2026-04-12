//
//  PromptTemplates.swift
//  Reader for Language Learner
//
//  Created by Codex on 11.02.2026.
//

import Foundation

enum PromptTemplates {

    // MARK: - Output Format

    /// Whether a module's output uses markdown or plain text.
    enum OutputFormat {
        /// No markdown — plain prose only.
        case plain
        /// Markdown allowed: **bold**, *italic*, numbered lists, bullet points.
        case markdown
    }

    // MARK: - System Prompt

    /// System prompt parameterized by language constraint and output format.
    /// Kept concise for fast prefill on small local models (Gemma 3 4B etc.).
    static func system(lang: OutputLanguage, format: OutputFormat = .plain, customPreamble: String = "") -> String {
        let formatRule: String
        switch format {
        case .plain:
            formatRule = "Plain text only."
        case .markdown:
            formatRule = "Use only the markdown pattern requested by the user prompt."
        }

        var base = """
        You are a fast dictionary assistant for language learners.
        \(lang.constraint)
        \(formatRule)
        Start with the answer immediately.
        Be compact and direct.
        No preamble, no commentary, no code fences.
        If unsure, write "\(lang.unknownFallback)".
        """

        let trimmedPreamble = customPreamble.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPreamble.isEmpty {
            base += "\n\(trimmedPreamble)"
        }

        return base
    }

    // MARK: - Output Language

    enum OutputLanguage {
        case englishOnly
        case turkishOnly
        case mixed  // EN fields + native-language fields side by side

        var constraint: String {
            switch self {
            case .englishOnly:
                return "Output only in English."
            case .turkishOnly:
                return "Output only in Turkish."
            case .mixed:
                return "EN fields in English only. TR fields in Turkish only."
            }
        }

        var unknownFallback: String {
            switch self {
            case .englishOnly, .mixed: return "Unknown"
            case .turkishOnly:         return "Bilinmiyor"
            }
        }
    }
}
