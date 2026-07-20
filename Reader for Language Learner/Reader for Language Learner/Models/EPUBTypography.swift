//
//  EPUBTypography.swift
//  Reader for Language Learner
//
//  Reading-typography preferences for the EPUB engine (font family, line
//  height, content width, justification). PDFs are fixed-layout — these
//  apply to EPUB only. All values persist as individual @AppStorage keys
//  and are bundled into an `EPUBTypography` value for the CSS builder.
//

import AppKit
import SwiftUI

/// Reader font override. `publisher` emits no font-family CSS at all, so
/// the book's own typography wins — every other case forces a system font
/// with a generic fallback in the stack.
enum EPUBFontFamily: String, CaseIterable, Identifiable {
    case publisher
    case charter
    case georgia
    case palatino
    case baskerville
    case helveticaNeue
    case sanFrancisco

    var id: String { rawValue }

    static let storageKey = "epubFontFamily"

    /// CSS font-family stack; nil = no override (publisher default).
    var cssFontFamily: String? {
        switch self {
        case .publisher: return nil
        case .charter: return "'Charter', serif"
        case .georgia: return "'Georgia', serif"
        case .palatino: return "'Palatino', serif"
        case .baskerville: return "'Baskerville', serif"
        case .helveticaNeue: return "'Helvetica Neue', sans-serif"
        case .sanFrancisco: return "-apple-system, sans-serif"
        }
    }

    /// Family name for the availability unit test (and preview rendering).
    /// nil where there is nothing to check (publisher, -apple-system).
    var fontFamilyName: String? {
        switch self {
        case .publisher, .sanFrancisco: return nil
        case .charter: return "Charter"
        case .georgia: return "Georgia"
        case .palatino: return "Palatino"
        case .baskerville: return "Baskerville"
        case .helveticaNeue: return "Helvetica Neue"
        }
    }

    var localizedTitle: String {
        switch self {
        case .publisher: return String(localized: "Publisher Default")
        case .charter: return "Charter"
        case .georgia: return "Georgia"
        case .palatino: return "Palatino"
        case .baskerville: return "Baskerville"
        case .helveticaNeue: return "Helvetica Neue"
        case .sanFrancisco: return "San Francisco"
        }
    }
}

/// Reading-column width presets, in CSS `em` units.
enum EPUBContentWidth: String, CaseIterable, Identifiable {
    case narrow
    case medium
    case wide

    var id: String { rawValue }

    static let storageKey = "epubContentWidth"

    var em: Int {
        switch self {
        case .narrow: return 36
        case .medium: return 42
        case .wide: return 52
        }
    }

    var localizedTitle: String {
        switch self {
        case .narrow: return String(localized: "Narrow")
        case .medium: return String(localized: "Medium")
        case .wide: return String(localized: "Wide")
        }
    }
}

/// The complete typography snapshot handed to `appearanceCSS`.
struct EPUBTypography: Equatable {
    var fontSize: Double = 18
    var lineHeight: Double = 1.6
    var widthEm: Int = EPUBContentWidth.medium.em
    /// CSS stack, nil = publisher default (no override emitted).
    var fontFamilyCSS: String? = nil
    var justified: Bool = false

    static let lineHeightKey = "epubLineHeight"
    static let justifiedKey = "epubJustified"

    /// Builds the snapshot from the stored preferences. Unknown enum
    /// rawValues fall back to defaults.
    static func stored(fontSize: Double) -> EPUBTypography {
        let defaults = UserDefaults.standard
        let family = defaults.string(forKey: EPUBFontFamily.storageKey)
            .flatMap(EPUBFontFamily.init) ?? .publisher
        let width = defaults.string(forKey: EPUBContentWidth.storageKey)
            .flatMap(EPUBContentWidth.init) ?? .medium
        let lineHeight = defaults.object(forKey: lineHeightKey) as? Double ?? 1.6
        return EPUBTypography(
            fontSize: fontSize,
            lineHeight: min(2.0, max(1.2, lineHeight)),
            widthEm: width.em,
            fontFamilyCSS: family.cssFontFamily,
            justified: defaults.bool(forKey: justifiedKey)
        )
    }
}
