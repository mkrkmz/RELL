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
    /// Kept concise for fast prefill on local models.
    static func system(lang: OutputLanguage, format: OutputFormat = .plain, customPreamble: String = "") -> String {
        let formatRule: String
        switch format {
        case .plain:
            formatRule = "Plain text only."
        case .markdown:
            formatRule = "Use only the markdown pattern requested by the user prompt."
        }

        var base = """
        You are a dictionary assistant for language learners.
        \(lang.constraint)
        \(formatRule)
        Answer directly and compactly — no preamble, no commentary, no code fences.
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
        /// The learner's configured target language — was hardcoded to
        /// English (`englishOnly`), which made every explanation module an
        /// English-teaching tool regardless of what the user studies.
        case target(Language)
        /// The learner's configured native language (any of the 12 supported
        /// languages) — was hardcoded to Turkish, which fought the user
        /// prompt's own `\(nativeLanguage.promptInstruction)` line for every
        /// non-Turkish native language.
        case native(Language)
        /// Target-language fields + native-language fields side by side
        /// (collocations). Structural labels stay literal English — they are
        /// parser targets (`ResultParser`), never localized in the prompt.
        case mixed(native: Language, target: Language)

        var constraint: String {
            switch self {
            case .target(let language):
                // Keep the English wording byte-identical to the old
                // `.englishOnly` constraint so English-target prompts don't drift.
                return language == .english
                    ? "Output only in English."
                    : "Output only in \(language.nativeName)."
            case .native(let language):
                return "Output only in \(language.nativeName)."
            case .mixed(let native, let target):
                return "Structural labels in English. Example sentences in \(target.rawValue) only. Meanings and translations in \(native.rawValue) only."
            }
        }

        var unknownFallback: String {
            switch self {
            case .target(let language), .native(let language):
                return language.unknownWord
            case .mixed:
                return "Unknown"
            }
        }
    }
}
