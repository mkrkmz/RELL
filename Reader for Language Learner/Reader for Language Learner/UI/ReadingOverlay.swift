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

import AppKit
import SwiftUI

extension PageTheme {
    /// The overlay's fill on this page, and whether that fill is dark.
    /// `.original` shows the document's own (white) pages, so its overlay
    /// is light whatever the system appearance — a dark bar over a white
    /// page read as a hole in it (live pass).
    var overlaySurface: (fill: SwiftUI.Color, isDark: Bool) {
        switch self {
        case .original: return (SwiftUI.Color.white, false)
        case .paper: return (SwiftUI.Color(red: 1.0, green: 0.992, blue: 0.969), false)    // #fffdf7
        case .sepia: return (SwiftUI.Color(red: 0.984, green: 0.961, blue: 0.902), false)  // #fbf5e6
        case .gray: return (SwiftUI.Color(red: 0.200, green: 0.200, blue: 0.212), true)    // #333336, darker than the page so it separates
        case .dark: return (SwiftUI.Color(red: 0.165, green: 0.165, blue: 0.165), true)    // #2a2a2a
        case .night: return (SwiftUI.Color(red: 0.122, green: 0.114, blue: 0.102), true)   // #1f1d1a
        }
    }
}

extension PageTheme {
    /// The inspector's background when it follows the page theme (v14 S2),
    /// and whether it's dark. Nil for `.original`: the system look stays.
    var inspectorSurface: (fill: SwiftUI.Color, isDark: Bool)? {
        switch self {
        case .original: return nil
        case .paper: return (SwiftUI.Color(red: 0.969, green: 0.949, blue: 0.902), false)  // #f7f2e6
        case .sepia: return (SwiftUI.Color(red: 0.945, green: 0.910, blue: 0.827), false)  // #f1e8d3
        case .gray: return (SwiftUI.Color(red: 0.247, green: 0.247, blue: 0.263), true)    // #3f3f43
        case .dark: return (SwiftUI.Color(red: 0.110, green: 0.110, blue: 0.110), true)    // #1c1c1c
        case .night: return (SwiftUI.Color(red: 0.086, green: 0.078, blue: 0.071), true)   // #161412
        }
    }

    /// The stored page theme — for AppKit hosts (popovers) that set their
    /// appearance before SwiftUI draws.
    static var stored: PageTheme {
        UserDefaults.standard.string(forKey: StorageKey.pageTheme).flatMap(PageTheme.init(rawValue:)) ?? .original
    }

    /// Light or dark AppKit appearance matching the overlay fill.
    var overlayAppearance: NSAppearance? {
        NSAppearance(named: overlaySurface.isDark ? .darkAqua : .aqua)
    }
}

/// Fill only, for content inside chrome that already has its own shape
/// (an NSPopover): the system draws the outline and arrow.
private struct ReadingOverlayFill: ViewModifier {
    @AppStorage(StorageKey.pageTheme) private var pageThemeRaw = PageTheme.original.rawValue

    func body(content: Content) -> some View {
        let (fill, isDark) = (PageTheme(rawValue: pageThemeRaw) ?? .original).overlaySurface
        content
            .environment(\.colorScheme, isDark ? .dark : .light)
            .background(fill)
    }
}

private struct ReadingOverlaySurface<S: InsettableShape>: ViewModifier {
    let shape: S
    var shadow: DS.ShadowStyle = DS.Shadow.float

    @AppStorage(StorageKey.pageTheme) private var pageThemeRaw = PageTheme.original.rawValue

    func body(content: Content) -> some View {
        let (fill, isDark) = (PageTheme(rawValue: pageThemeRaw) ?? .original).overlaySurface

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

    /// The reading-overlay fill for content inside a popover over the text.
    func dsReadingOverlayFill() -> some View {
        modifier(ReadingOverlayFill())
    }
}
