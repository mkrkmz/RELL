//
//  AccentChoice.swift
//  Reader for Language Learner
//
//  User-selectable app accent color. `DS.Color.accent` resolves through
//  this, and a shared tint modifier at every scene root keeps native
//  controls and the SwiftUI tree in sync when the choice changes.
//

import AppKit
import SwiftUI

enum AccentChoice: String, CaseIterable, Identifiable {
    case system
    case blue
    case indigo
    case purple
    case pink
    case red
    case orange
    case yellow
    case green
    case teal

    var id: String { rawValue }

    static let storageKey = "accentChoice"

    /// The stored choice; unknown/missing rawValues fall back to `.system`.
    static var current: AccentChoice {
        guard let raw = UserDefaults.standard.string(forKey: storageKey),
              let choice = AccentChoice(rawValue: raw) else { return .system }
        return choice
    }

    /// nil for `.system` — callers fall back to `.accentColor` so the empty
    /// asset-catalog entry keeps resolving to the macOS system accent.
    /// NSColor system colors adapt to light/dark automatically.
    var color: Color? {
        switch self {
        case .system: return nil
        case .blue:   return Color(nsColor: .systemBlue)
        case .indigo: return Color(nsColor: .systemIndigo)
        case .purple: return Color(nsColor: .systemPurple)
        case .pink:   return Color(nsColor: .systemPink)
        case .red:    return Color(nsColor: .systemRed)
        case .orange: return Color(nsColor: .systemOrange)
        case .yellow: return Color(nsColor: .systemYellow)
        case .green:  return Color(nsColor: .systemGreen)
        case .teal:   return Color(nsColor: .systemTeal)
        }
    }

    /// The color every accent consumer should paint with right now.
    var resolvedColor: Color { color ?? .accentColor }

    var localizedTitle: String {
        switch self {
        case .system: return String(localized: "System")
        case .blue:   return String(localized: "Blue")
        case .indigo: return String(localized: "Indigo")
        case .purple: return String(localized: "Purple")
        case .pink:   return String(localized: "Pink")
        case .red:    return String(localized: "Red")
        case .orange: return String(localized: "Orange")
        case .yellow: return String(localized: "Yellow")
        case .green:  return String(localized: "Green")
        case .teal:   return String(localized: "Teal")
        }
    }
}

// MARK: - Scene-root tint

/// Applied at every scene root (and the Quick Lookup NSPanel's hosting
/// view, which lives outside the scene tree). The `@AppStorage` observation
/// is what re-renders the tree on an accent change — `DS.Color.accent` is a
/// static computed property and re-reads the stored choice during that
/// re-render; `.tint` makes native controls (toggles, pickers, progress)
/// follow as well.
struct AccentTintModifier: ViewModifier {
    @AppStorage(AccentChoice.storageKey) private var accentRaw = AccentChoice.system.rawValue

    func body(content: Content) -> some View {
        content.tint((AccentChoice(rawValue: accentRaw) ?? .system).resolvedColor)
    }
}

extension View {
    func rellAccentTint() -> some View {
        modifier(AccentTintModifier())
    }
}
