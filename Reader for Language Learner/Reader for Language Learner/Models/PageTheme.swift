//
//  PageTheme.swift
//  Reader for Language Learner
//
//  Created by Codex on 16.02.2026.
//

import AppKit
import SwiftUI
import CoreImage

/// Controls the appearance of the PDF page content and surrounding area.
enum PageTheme: String, CaseIterable, Identifiable {
    case original = "original"
    case paper = "paper"
    case sepia = "sepia"
    case gray = "gray"
    case dark = "dark"
    case night = "night"

    var id: String { rawValue }

    /// Raw English name — rawValues back `@AppStorage("pageTheme")`, keep
    /// stable. Visible UI goes through `localizedTitle`.
    var displayName: String {
        switch self {
        case .original: return "Original"
        case .paper: return "Paper"
        case .sepia: return "Sepia"
        case .gray: return "Gray"
        case .dark: return "Dark"
        case .night: return "Night"
        }
    }

    var localizedTitle: String {
        switch self {
        case .original: return String(localized: "Original")
        case .paper: return String(localized: "Paper")
        case .sepia: return String(localized: "Sepia")
        case .gray: return String(localized: "Gray")
        case .dark: return String(localized: "Dark")
        case .night: return String(localized: "Night")
        }
    }

    var iconName: String {
        switch self {
        case .original: return "doc.text"
        case .paper: return "doc.plaintext"
        case .sepia: return "scroll"
        case .gray: return "circle.lefthalf.filled"
        case .dark: return "moon.fill"
        case .night: return "moon.stars.fill"
        }
    }

    /// Themes whose reading surface is dark enough that highlighted text
    /// needs light ink (dark ink over a translucent mark is unreadable).
    var usesLightInk: Bool {
        switch self {
        case .dark, .night: return true
        case .original, .paper, .sepia, .gray: return false
        }
    }

    // MARK: - PDF View Colors

    /// Background color for the PDFView container area (around pages).
    var backgroundColor: NSColor {
        switch self {
        case .original: return NSColor(white: 0.92, alpha: 1) // Light Gray
        case .paper: return NSColor(red: 0.97, green: 0.95, blue: 0.91, alpha: 1) // Warm Off-White
        case .sepia: return NSColor(red: 0.96, green: 0.93, blue: 0.86, alpha: 1) // Warm Tan
        case .gray: return NSColor(white: 0.35, alpha: 1) // Mid Gray
        case .dark: return .black // Pure Black
        case .night: return NSColor(white: 0.05, alpha: 1) // Near Black
        }
    }

    // MARK: - Overlay Settings

    /// Color of the overlay view.
    var overlayColor: NSColor? {
        switch self {
        case .original: return nil
        case .paper: return NSColor(red: 0.55, green: 0.48, blue: 0.36, alpha: 0.07) // Faint warm tint
        case .sepia: return NSColor(red: 0.5, green: 0.4, blue: 0.2, alpha: 0.15) // Subtle Sepia Tint
        case .gray: return NSColor(white: 0.72, alpha: 0.55) // Dims white pages, keeps black text legible
        case .dark: return .white // White overlay for difference blending (inversion)
        case .night: return NSColor(red: 0.95, green: 0.91, blue: 0.85, alpha: 1) // Warm inversion — off-white difference base
        }
    }

    /// Core Image compositing filter name for the overlay layer.
    var overlayBlendMode: String? {
        switch self {
        case .original: return nil
        case .paper: return "CIMultiplyBlendMode" // Barely-there warm paper cast
        case .sepia: return "CIMultiplyBlendMode" // Darken white pages with sepia
        case .gray: return "CIMultiplyBlendMode" // Pull the white page down to gray
        case .dark: return "CIDifferenceBlendMode" // Invert colors: Abs(Background - White)
        case .night: return "CIDifferenceBlendMode" // Inversion against warm white → warm dark page
        }
    }

    // MARK: - EPUB CSS Colors

    /// Background / text / link colors for the EPUB appearance stylesheet.
    /// nil = hands-off (`.original` lets the book's own colors show).
    var epubColors: (background: String, text: String, link: String)? {
        switch self {
        case .original: return nil
        case .paper: return ("#faf6ec", "#3a3226", "#8a5a2b")
        case .sepia: return ("#f4ecd8", "#5b4636", "#8a5a2b")
        case .gray: return ("#4a4a4e", "#d6d6d6", "#9ec1e8")
        case .dark: return ("#1e1e1e", "#d8d8d8", "#7db4e6")
        case .night: return ("#121212", "#c9c0b0", "#d0a860")
        }
    }
}
