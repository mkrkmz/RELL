//
//  ReadingOverlay.swift
//  Reader for Language Learner
//
//  The surface for controls that float over the text being read — the
//  selection bar, the speech bar, the Zen bar (v14 S1). Glass refracts what
//  is behind it; behind these bars are lines of text, which bent through the
//  glass and ran into the bar's own labels (live pass, every page theme).
//  So these bars keep the glass shape — capsule, hairline, soft shadow —
//  but are filled opaque, in a tone of the page theme, so they read as part
//  of the page and stay equally legible on all six themes. Glass stays for
//  chrome with nothing to read behind it (toolbar, sidebar, inspector).
//

import SwiftUI

extension PageTheme {
    /// The overlay's fill on this page, and whether that fill is dark.
    /// `.original` follows the system appearance.
    var overlaySurface: (fill: SwiftUI.Color, isDark: Bool)? {
        switch self {
        case .original: return nil
        case .paper: return (SwiftUI.Color(red: 1.0, green: 0.992, blue: 0.969), false)    // #fffdf7
        case .sepia: return (SwiftUI.Color(red: 0.984, green: 0.961, blue: 0.902), false)  // #fbf5e6
        case .gray: return (SwiftUI.Color(red: 0.200, green: 0.200, blue: 0.212), true)    // #333336, darker than the page so it separates
        case .dark: return (SwiftUI.Color(red: 0.165, green: 0.165, blue: 0.165), true)    // #2a2a2a
        case .night: return (SwiftUI.Color(red: 0.122, green: 0.114, blue: 0.102), true)   // #1f1d1a
        }
    }
}

private struct ReadingOverlaySurface<S: InsettableShape>: ViewModifier {
    let shape: S
    var shadow: DS.ShadowStyle = DS.Shadow.float

    @AppStorage(StorageKey.pageTheme) private var pageThemeRaw = PageTheme.original.rawValue
    @Environment(\.colorScheme) private var systemScheme

    func body(content: Content) -> some View {
        let theme = PageTheme(rawValue: pageThemeRaw) ?? .original
        let surface = theme.overlaySurface
        let isDark = surface?.isDark ?? (systemScheme == .dark)
        let fill = surface?.fill ?? (isDark
            ? SwiftUI.Color(red: 0.173, green: 0.173, blue: 0.180)   // #2c2c2e
            : SwiftUI.Color.white)

        content
            // Labels and icons use .primary/.secondary; this makes them
            // light on the dark fills and dark on the light ones.
            .environment(\.colorScheme, isDark ? .dark : .light)
            .background(fill, in: shape)
            .overlay(shape.strokeBorder(SwiftUI.Color.primary.opacity(isDark ? 0.16 : 0.12), lineWidth: 0.6))
            .shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}

extension View {
    /// Opaque, page-themed surface for a control floating over text. See
    /// the file comment for why these aren't glass.
    func dsReadingOverlay<S: InsettableShape>(_ shape: S, shadow: DS.ShadowStyle = DS.Shadow.float) -> some View {
        modifier(ReadingOverlaySurface(shape: shape, shadow: shadow))
    }
}
