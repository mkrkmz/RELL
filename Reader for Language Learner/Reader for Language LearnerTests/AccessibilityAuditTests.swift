//
//  AccessibilityAuditTests.swift
//  Reader for Language LearnerTests
//
//  v14 Sprint 4: every button drawn only as an icon has a VoiceOver name.
//  Without one VoiceOver reads the symbol's name ("chevron up") — or
//  nothing. `.help` is a tooltip, not a name. The test reads the app's
//  sources (found from this file's path), so it runs the same locally and
//  on CI; a new unnamed icon button fails it with its file and line.
//

import Foundation
import XCTest

final class AccessibilityAuditTests: XCTestCase {

    func testEveryIconOnlyButtonHasAnAccessibilityLabel() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Reader for Language Learner")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
        XCTAssertGreaterThan(files.count, 100, "app sources not found at \(sources.path)")

        var unnamed: [String] = []
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            // An empty title is no name either: `Button("", systemImage:)`.
            for (index, line) in lines.enumerated() where line.contains("Button(\"\", systemImage") {
                unnamed.append("\(file.lastPathComponent):\(index + 1) empty title")
            }
            for (index, line) in lines.enumerated() where Self.opensIconButton(line) {
                if let finding = Self.unnamedButton(in: lines, at: index) {
                    unnamed.append("\(file.lastPathComponent):\(index + 1) \(finding)")
                }
            }
        }
        XCTAssertEqual(unnamed, [], "icon-only buttons without .accessibilityLabel:\n" + unnamed.joined(separator: "\n"))
    }

    /// `Button {`, `Button(action:`, `Button(role: …) {` — not `Button("Title"`.
    private static func opensIconButton(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let range = trimmed.range(of: "Button") else { return false }
        let after = trimmed[range.upperBound...]
        return after.hasPrefix(" {") || after.hasPrefix("(action:") || (after.hasPrefix("(role:") && after.hasSuffix("{"))
    }

    /// The label is the button's body (or what follows `label:`); a label of
    /// only an `Image(systemName:)` needs a name among the modifiers that
    /// follow the closing brace.
    private static func unnamedButton(in lines: [String], at start: Int) -> String? {
        let indent = lines[start].prefix { $0 == " " }.count
        var end = start + 1
        while end < lines.count, end < start + 80 {
            let line = lines[end]
            let lineIndent = line.prefix { $0 == " " }.count
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if lineIndent == indent, trimmed.hasPrefix("}"), !trimmed.hasPrefix("} label") { break }
            end += 1
        }
        var label = lines[(start + 1)..<min(end, lines.count)].joined(separator: "\n")
        if let range = label.range(of: "label:") { label = String(label[range.upperBound...]) }
        guard label.contains("Image(systemName"),
              !label.contains("Text("), !label.contains("Label(")
        else { return nil }

        var modifiers: [String] = []
        var next = end + 1
        while next < lines.count, lines[next].trimmingCharacters(in: .whitespaces).hasPrefix(".") {
            modifiers.append(lines[next]); next += 1
        }
        let joined = modifiers.joined()
        return joined.contains("accessibilityLabel") || joined.contains("accessibilityHidden") ? nil : "unnamed"
    }
}
