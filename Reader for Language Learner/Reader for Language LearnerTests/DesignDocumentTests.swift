//
//  DesignDocumentTests.swift
//  Reader for Language LearnerTests
//
//  `DESIGN.md` against the design system it was written from (Roadmap v20
//  Sprint 0): the spacing and corner steps, the two fixed hues and the page
//  theme table must match `DS` and `PageTheme`. When a token changes and
//  the document doesn't — or the other way round — this goes red.
//

import AppKit
import SwiftUI
import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class DesignDocumentTests: XCTestCase {

    private var document: String {
        get throws {
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()      // Reader for Language LearnerTests
                .deletingLastPathComponent()      // Reader for Language Learner (project)
                .deletingLastPathComponent()      // repository root
                .appendingPathComponent("DESIGN.md")
            return try String(contentsOf: url, encoding: .utf8)
        }
    }

    /// The `group:` block of the frontmatter as name → value, e.g. `md` → `10px`.
    private func frontmatterGroup(_ group: String) throws -> [String: String] {
        let lines = try document.components(separatedBy: "\n")
        guard let start = lines.firstIndex(of: "\(group):") else {
            XCTFail("DESIGN.md has no \(group) group")
            return [:]
        }
        var values: [String: String] = [:]
        for line in lines[(start + 1)...] {
            guard line.hasPrefix("  "), !line.hasPrefix("    ") else { break }
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            values[String(parts[0])] = parts[1].trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return values
    }

    private func points(_ value: String?) -> Double? {
        value.flatMap { Double($0.replacingOccurrences(of: "px", with: "")) }
    }

    private func hex(_ color: NSColor) -> String {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        return String(format: "#%02X%02X%02X",
                      Int((rgb.redComponent * 255).rounded()),
                      Int((rgb.greenComponent * 255).rounded()),
                      Int((rgb.blueComponent * 255).rounded()))
    }

    func testSpacingMatchesTheDesignSystem() throws {
        let tokens: [String: CGFloat] = [
            "hairline": DS.Spacing.hairline, "xxs": DS.Spacing.xxs, "xs": DS.Spacing.xs,
            "sm": DS.Spacing.sm, "md": DS.Spacing.md, "lg": DS.Spacing.lg,
            "xl": DS.Spacing.xl, "xxl": DS.Spacing.xxl, "xxxl": DS.Spacing.xxxl,
        ]
        let documented = try frontmatterGroup("spacing")
        XCTAssertEqual(Set(documented.keys), Set(tokens.keys))
        for (name, value) in tokens {
            XCTAssertEqual(points(documented[name]), Double(value), "spacing.\(name)")
        }
    }

    func testCornersMatchTheDesignSystem() throws {
        let tokens: [String: CGFloat] = [
            "cell": DS.Radius.cell, "hairline": DS.Radius.hairline, "cover": DS.Radius.cover,
            "xs": DS.Radius.xs, "sm": DS.Radius.sm, "md": DS.Radius.md, "lg": DS.Radius.lg, "xl": DS.Radius.xl,
        ]
        let documented = try frontmatterGroup("rounded")
        XCTAssertEqual(Set(documented.keys), Set(tokens.keys))
        for (name, value) in tokens {
            XCTAssertEqual(points(documented[name]), Double(value), "rounded.\(name)")
        }
    }

    func testTheFixedHuesMatchTheDesignSystem() throws {
        let colors = try frontmatterGroup("colors")
        XCTAssertEqual(colors["brown"], hex(NSColor(DS.Color.brown)))
        XCTAssertEqual(colors["amber"], hex(NSColor(DS.Color.amber)))
    }

    /// The Themes table and the default (Original) tokens in the frontmatter.
    func testThePageThemeTableMatchesThePageThemes() throws {
        let colors = try frontmatterGroup("colors")
        XCTAssertEqual(colors["page-background"], hex(PageTheme.original.backgroundColor))
        XCTAssertEqual(colors["reading-overlay"], hex(NSColor(PageTheme.original.overlaySurface.fill)))

        let rows = try document.components(separatedBy: "\n").filter { $0.hasPrefix("| ") && $0.contains("#") }
        for theme in PageTheme.allCases {
            let row = try XCTUnwrap(rows.first { $0.hasPrefix("| \(theme.rawValue.capitalized) |") },
                                    "no Themes row for \(theme.rawValue)")
            let cells = row.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            XCTAssertEqual(cells[1], hex(theme.backgroundColor), "\(theme.rawValue) page-background")
            XCTAssertEqual(cells[2], hex(NSColor(theme.overlaySurface.fill)), "\(theme.rawValue) reading-overlay")
        }
    }
}
