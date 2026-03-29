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
    static func system(lang: OutputLanguage, format: OutputFormat = .plain) -> String {
        let formatRule: String
        switch format {
        case .plain:
            formatRule = "- Plain text only. No markdown, no headings, no bullets, no numbered lists."
        case .markdown:
            formatRule = "- Use markdown exactly as shown in the user prompt: bold with **, italic with *, numbered lists (1. 2. 3.), bullets with -. No code fences or triple backticks."
        }

        return """
        You are a lexicologist and language coach.
        RULES:
        \(lang.constraint)
        \(formatRule)
        - No greetings, introductions, or commentary.
        - No code fences or triple backticks.
        - If unsure about a fact, write "\(lang.unknownFallback)" instead of guessing.
        - Output ONLY the requested content. Stop immediately after.
        """
    }

    // MARK: - Output Language

    enum OutputLanguage {
        case englishOnly
        case turkishOnly
        case mixed  // EN fields + native-language fields side by side

        var constraint: String {
            switch self {
            case .englishOnly:
                return "- Output ONLY in English. No other languages."
            case .turkishOnly:
                return "- Output ONLY in Turkish. No English words."
            case .mixed:
                return "- EN-labeled fields must be English only. TR-labeled fields must be Turkish only. Never mix languages within a field."
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
