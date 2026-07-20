//
//  AppTheme.swift
//  Reader for Language Learner
//
//  Created by Codex on 16.02.2026.
//

import AppKit
import SwiftUI

/// Controls the overall application interface appearance (Toolbar, Sidebar, Inspector).
enum AppTheme: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var localizedTitle: String {
        switch self {
        case .system: return String(localized: "System")
        case .light: return String(localized: "Light")
        case .dark: return String(localized: "Dark")
        }
    }

    var iconName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    /// The SwiftUI color scheme to apply. `nil` = follow system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// AppKit appearance for the process-wide `NSApp.appearance` override.
    /// `nil` = follow system. Applied globally (not per-window
    /// `.preferredColorScheme`) so Settings, the Review window, the
    /// MenuBarExtra, and the Quick Lookup NSPanel all follow the choice.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    /// The stored choice; unknown/missing rawValues fall back to `.system`.
    static var current: AppTheme {
        guard let raw = UserDefaults.standard.string(forKey: "appTheme"),
              let theme = AppTheme(rawValue: raw) else { return .system }
        return theme
    }

    /// Pushes the stored theme onto the whole process.
    @MainActor
    static func applyCurrent() {
        NSApp.appearance = current.nsAppearance
    }
}
