//
//  MarkdownUtils.swift
//  Reader for Language Learner
//
//  Created by Codex on 11.02.2026.
//

import Foundation

enum MarkdownUtils {
    static func sanitizeLLMOutput(_ text: String) -> String {
        var lines = text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
        guard !lines.isEmpty else { return "" }

        let trimmedLines = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let firstFenceIndex = trimmedLines.firstIndex(where: { $0.hasPrefix("```") }),
           let lastFenceIndex = trimmedLines.lastIndex(where: { $0.hasPrefix("```") }),
           lastFenceIndex > firstFenceIndex {
            lines.remove(at: lastFenceIndex)
            lines.remove(at: firstFenceIndex)
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
