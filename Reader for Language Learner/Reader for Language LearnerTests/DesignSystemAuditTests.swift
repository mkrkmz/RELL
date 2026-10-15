//
//  DesignSystemAuditTests.swift
//  Reader for Language LearnerTests
//
//  The design-system audit CLAUDE.md describes, as a test (v18 S1): no raw
//  fonts, numeric paddings or corner radii, and no named colours outside
//  `DS`. A deliberate one-off carries `// DS-exempt: <reason>` on the line
//  or the two above it. Runs in CI, so the rule holds without a hook.
//

import XCTest

final class DesignSystemAuditTests: XCTestCase {

    private struct Rule {
        let name: String
        let pattern: String
    }

    private let rules = [
        Rule(name: "raw font", pattern: #"\.font\(\.system\(|\?\s*\.system\(size:|:\s*\.system\(size:"#),
        Rule(name: "numeric padding", pattern: #"\.padding\((\.[a-zA-Z]+,\s*)?[0-9]+(\.[0-9]+)?\)"#),
        Rule(name: "numeric corner radius", pattern: #"cornerRadius:\s*[0-9]+(\.[0-9]+)?\b"#),
        Rule(name: "named colour", pattern: #"((?<!DS\.)Color\.(red|orange|yellow|green|mint|teal|cyan|blue|indigo|purple|pink|brown|gray)\b|\.foregroundStyle\(\.(red|orange|yellow|green|blue|purple|pink|gray)\))"#),
    ]

    /// Files that define the palette itself.
    private let exemptFiles: Set<String> = ["DesignSystem.swift", "DSButtonStyles.swift", "ReadingOverlay.swift"]

    private var sourceRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()           // Reader for Language LearnerTests
            .deletingLastPathComponent()           // Reader for Language Learner (project)
            .appendingPathComponent("Reader for Language Learner")
    }

    func testTheAppUsesDesignTokens() throws {
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: sourceRoot, includingPropertiesForKeys: nil))
        var findings: [String] = []
        var scanned = 0
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            guard !exemptFiles.contains(url.lastPathComponent) else { continue }
            scanned += 1
            let lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") { continue }
                for rule in rules where line.range(of: rule.pattern, options: .regularExpression) != nil {
                    let context = lines[max(0, index - 2)...index].joined(separator: "\n")
                    guard !context.contains("DS-exempt") else { continue }
                    findings.append("\(url.lastPathComponent):\(index + 1) \(rule.name): \(trimmed)")
                }
            }
        }
        XCTAssertGreaterThan(scanned, 100, "found the app's sources at \(sourceRoot.path)")
        XCTAssertTrue(findings.isEmpty, "Use DS tokens (or `// DS-exempt: <reason>`):\n" + findings.joined(separator: "\n"))
    }
}
