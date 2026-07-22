//
//  PDFLayoutMode.swift
//  Reader for Language Learner
//

import PDFKit

/// PDF page layout choice (View menu / toolbar). Named apart from PDFKit's
/// own `PDFDisplayMode` to avoid shadowing it in files that `import PDFKit`.
enum PDFLayoutMode: String, CaseIterable, Identifiable {
    case single = "single"
    case twoUp = "twoUp"

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .single: return String(localized: "Single Page")
        case .twoUp: return String(localized: "Two Pages")
        }
    }

    var iconName: String {
        switch self {
        case .single: return "doc.plaintext"
        case .twoUp: return "book"
        }
    }

    /// Continuous variants in both cases — scroll behavior is unchanged,
    /// only the page-per-row count differs.
    var kitDisplayMode: PDFDisplayMode {
        switch self {
        case .single: return .singlePageContinuous
        case .twoUp: return .twoUpContinuous
        }
    }
}
