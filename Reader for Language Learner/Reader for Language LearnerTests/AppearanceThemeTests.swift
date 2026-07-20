//
//  AppearanceThemeTests.swift
//  Reader for Language LearnerTests
//
//  Sprint v1.25.0 theme infrastructure: page-theme presets, accent choice,
//  EPUB typography, and the appearance CSS builder.
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class AppearanceThemeTests: XCTestCase {

    // MARK: - RawValue fallbacks (downgrade / corrupted defaults safety)

    func testUnknownPageThemeRawValueFallsBack() {
        XCTAssertNil(PageTheme(rawValue: "does-not-exist"))
        XCTAssertEqual(PageTheme(rawValue: "does-not-exist") ?? .original, .original)
        // New presets decode by their stable rawValues.
        XCTAssertEqual(PageTheme(rawValue: "paper"), .paper)
        XCTAssertEqual(PageTheme(rawValue: "gray"), .gray)
        XCTAssertEqual(PageTheme(rawValue: "night"), .night)
    }

    func testUnknownAccentChoiceFallsBackToSystem() {
        XCTAssertNil(AccentChoice(rawValue: "hotpink"))
        XCTAssertEqual(AccentChoice(rawValue: "hotpink") ?? .system, .system)
        XCTAssertNil(AccentChoice.system.color, "system must defer to .accentColor")
        for choice in AccentChoice.allCases where choice != .system {
            XCTAssertNotNil(choice.color, "\(choice.rawValue) must supply a concrete color")
        }
    }

    func testUnknownTypographyEnumsFallBack() {
        XCTAssertEqual(EPUBFontFamily(rawValue: "comic-sans") ?? .publisher, .publisher)
        XCTAssertEqual(EPUBContentWidth(rawValue: "ultrawide") ?? .medium, .medium)
        XCTAssertEqual(EPUBContentWidth.narrow.em, 36)
        XCTAssertEqual(EPUBContentWidth.medium.em, 42)
        XCTAssertEqual(EPUBContentWidth.wide.em, 52)
    }

    // MARK: - Highlight ink

    func testHighlightInkPerTheme() {
        for theme in PageTheme.allCases {
            let ink = EPUBViewManager.highlightInk(for: theme)
            if theme.usesLightInk {
                XCTAssertEqual(ink, "#e8e8e8", "\(theme.rawValue) is a dark surface — needs light ink")
            } else {
                XCTAssertEqual(ink, "#1d1d1f", "\(theme.rawValue) is a light surface — needs dark ink")
            }
        }
        XCTAssertTrue(PageTheme.dark.usesLightInk)
        XCTAssertTrue(PageTheme.night.usesLightInk)
        XCTAssertFalse(PageTheme.paper.usesLightInk)
        XCTAssertFalse(PageTheme.gray.usesLightInk)
    }

    // MARK: - PDF overlay completeness

    func testEveryNonOriginalThemeHasOverlayAndBlendMode() {
        for theme in PageTheme.allCases {
            if theme == .original {
                XCTAssertNil(theme.overlayColor)
                XCTAssertNil(theme.overlayBlendMode)
            } else {
                XCTAssertNotNil(theme.overlayColor, theme.rawValue)
                XCTAssertNotNil(theme.overlayBlendMode, theme.rawValue)
            }
        }
    }

    // MARK: - appearanceCSS

    func testAppearanceCSSContainsThemeColors() {
        let typography = EPUBTypography()
        for theme in PageTheme.allCases {
            let css = EPUBViewManager.appearanceCSS(theme: theme, typography: typography)
            if let colors = theme.epubColors {
                XCTAssertTrue(css.contains(colors.background), "\(theme.rawValue) background missing")
                XCTAssertTrue(css.contains(colors.text), "\(theme.rawValue) text color missing")
                XCTAssertTrue(css.contains(colors.link), "\(theme.rawValue) link color missing")
            } else {
                XCTAssertTrue(css.contains("#ffffff"), "original keeps the white surface")
            }
        }
    }

    func testAppearanceCSSHonorsTypography() {
        let typography = EPUBTypography(
            fontSize: 21, lineHeight: 1.8, widthEm: 52,
            fontFamilyCSS: "'Georgia', serif", justified: true
        )
        let css = EPUBViewManager.appearanceCSS(theme: .sepia, typography: typography)
        XCTAssertTrue(css.contains("font-size: 21px"))
        XCTAssertTrue(css.contains("line-height: 1.8"))
        XCTAssertTrue(css.contains("max-width: 52em"))
        XCTAssertTrue(css.contains("font-family: 'Georgia', serif !important"))
        XCTAssertTrue(css.contains("text-align: justify"))
    }

    func testPublisherDefaultEmitsNoFontOverride() {
        let typography = EPUBTypography()   // fontFamilyCSS nil, justified false
        let css = EPUBViewManager.appearanceCSS(theme: .original, typography: typography)
        XCTAssertFalse(css.contains("font-family"), "publisher default must not force a font")
        XCTAssertFalse(css.contains("text-align: justify"))
        XCTAssertTrue(css.contains("font-size: 18px"))
        XCTAssertTrue(css.contains("line-height: 1.6"))
        XCTAssertTrue(css.contains("max-width: 42em"))
    }

    // MARK: - Stored typography snapshot

    func testStoredTypographyReadsDefaultsAndClamps() {
        let defaults = UserDefaults.standard
        let keys = [EPUBFontFamily.storageKey, EPUBContentWidth.storageKey,
                    EPUBTypography.lineHeightKey, EPUBTypography.justifiedKey]
        let saved = keys.map { ($0, defaults.object(forKey: $0)) }
        defer { for (k, v) in saved { defaults.set(v, forKey: k) } }

        defaults.set("georgia", forKey: EPUBFontFamily.storageKey)
        defaults.set("wide", forKey: EPUBContentWidth.storageKey)
        defaults.set(5.0, forKey: EPUBTypography.lineHeightKey)   // out of range → clamp
        defaults.set(true, forKey: EPUBTypography.justifiedKey)

        let typography = EPUBTypography.stored(fontSize: 20)
        XCTAssertEqual(typography.fontSize, 20)
        XCTAssertEqual(typography.lineHeight, 2.0, "line height must clamp to 1.2...2.0")
        XCTAssertEqual(typography.widthEm, 52)
        XCTAssertEqual(typography.fontFamilyCSS, "'Georgia', serif")
        XCTAssertTrue(typography.justified)
    }

    // MARK: - Font availability (guards against a macOS release dropping one)

    func testReaderFontFamiliesAreInstalled() {
        let installed = Set(NSFontManager.shared.availableFontFamilies)
        for family in EPUBFontFamily.allCases {
            guard let name = family.fontFamilyName else { continue }
            XCTAssertTrue(
                installed.contains(name),
                "\(name) is not installed — CSS falls back to the generic family, but the picker promises it"
            )
        }
    }

    // MARK: - Localized titles never fall through to raw values

    func testLocalizedTitlesExistForAllCases() {
        for theme in PageTheme.allCases {
            XCTAssertFalse(theme.localizedTitle.isEmpty)
        }
        for theme in AppTheme.allCases {
            XCTAssertFalse(theme.localizedTitle.isEmpty)
        }
        for choice in AccentChoice.allCases {
            XCTAssertFalse(choice.localizedTitle.isEmpty)
        }
        for family in EPUBFontFamily.allCases {
            XCTAssertFalse(family.localizedTitle.isEmpty)
        }
    }
}
