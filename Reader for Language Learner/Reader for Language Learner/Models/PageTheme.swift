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
    case sepia = "sepia"
    case dark = "dark"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .original: return "Original"
        case .sepia: return "Sepia"
        case .dark: return "Dark"
        }
    }

    var iconName: String {
        switch self {
        case .original: return "doc.text"
        case .sepia: return "scroll"
        case .dark: return "moon.fill"
        }
    }

    // MARK: - PDF View Colors

    /// Background color for the PDFView container area (around pages).
    var backgroundColor: NSColor {
        switch self {
        case .original: return NSColor(white: 0.92, alpha: 1) // Light Gray
        case .sepia: return NSColor(red: 0.96, green: 0.93, blue: 0.86, alpha: 1) // Warm Tan
        case .dark: return .black // Pure Black
        }
    }

    // MARK: - Overlay Settings

    /// Color of the overlay view.
    var overlayColor: NSColor? {
        switch self {
        case .original: return nil
        case .sepia: return NSColor(red: 0.5, green: 0.4, blue: 0.2, alpha: 0.15) // Subtle Sepia Tint
        case .dark: return .white // White overlay for difference blending (inversion)
        }
    }

    /// Core Image compositing filter name for the overlay layer.
    var overlayBlendMode: String? {
        switch self {
        case .original: return nil
        case .sepia: return "CIMultiplyBlendMode" // Darken white pages with sepia
        case .dark: return "CIDifferenceBlendMode" // Invert colors: Abs(Background - White)
        }
    }
}
