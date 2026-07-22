//
//  EPUBAppearanceTests.swift
//  Reader for Language LearnerTests
//
//  Locks in the theme-forcing behavior of the injected reader CSS. The bug
//  these guard against: publisher stylesheets set `body { background:#fff }`,
//  so a theme that doesn't force the surface + text with `!important` leaves
//  the page white regardless of the selected page theme.
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class EPUBAppearanceTests: XCTestCase {

    func testDarkThemeForcesSurfaceAndTextWithImportant() {
        let css = EPUBViewManager.appearanceCSS(theme: .dark, typography: EPUBTypography())

        XCTAssertTrue(css.contains("background-color: #1e1e1e !important"),
                      "dark theme must force the page background")
        XCTAssertTrue(css.contains("color: #d8d8d8 !important"),
                      "dark theme must force the body text color")
        // Descendant text elements inherit the forced color, also !important,
        // so publisher-colored <p>/<span> can't defeat the theme.
        XCTAssertTrue(css.contains("color: inherit !important"))
        XCTAssertTrue(css.contains("body p"), "descendant text elements are targeted explicitly")
    }

    func testSepiaThemeForcesItsOwnPalette() {
        let css = EPUBViewManager.appearanceCSS(theme: .sepia, typography: EPUBTypography())
        XCTAssertTrue(css.contains("background-color: #f4ecd8 !important"))
        XCTAssertTrue(css.contains("color: #5b4636 !important"))
    }

    func testOriginalThemeStaysHandsOffAndDoesNotForceTextColor() {
        let css = EPUBViewManager.appearanceCSS(theme: .original, typography: EPUBTypography())
        // Original keeps a white surface but must NOT override the book's own
        // text colors — no forced inherit rule.
        XCTAssertTrue(css.contains("background-color: #ffffff !important"))
        XCTAssertFalse(css.contains("color: inherit !important"),
                       "original theme should let the book's own colors show")
    }

    func testFontSizeIsReflectedInLayout() {
        let css = EPUBViewManager.appearanceCSS(theme: .dark, typography: EPUBTypography(fontSize: 22))
        XCTAssertTrue(css.contains("font-size: 22px"))
    }

    func testHighlightInkIsLightOnDarkThemeAndDarkElsewhere() {
        // Dark ink over a translucent mark on a dark page is unreadable —
        // the regression this guards against (marks hardcoded #1d1d1f).
        XCTAssertEqual(EPUBViewManager.highlightInk(for: .dark), "#e8e8e8")
        XCTAssertEqual(EPUBViewManager.highlightInk(for: .original), "#1d1d1f")
        XCTAssertEqual(EPUBViewManager.highlightInk(for: .sepia), "#1d1d1f")
    }

    // MARK: - Saved-word mark color

    func testSavedWordMarkColorDiffersByThemeBrightness() {
        for theme in PageTheme.allCases {
            let color = EPUBViewManager.savedWordMarkColor(for: theme)
            XCTAssertTrue(color.hasPrefix("rgba("), "\(theme.rawValue) must produce a valid rgba() color")
            if theme.usesLightInk {
                XCTAssertEqual(color, "rgba(150, 179, 255, 0.75)", "\(theme.rawValue) is a dark surface — needs the lighter mark tint")
            } else {
                XCTAssertEqual(color, "rgba(51, 92, 209, 0.65)", "\(theme.rawValue) is a light surface — needs the darker mark tint")
            }
        }
    }
}
