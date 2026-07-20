//
//  DesignSystem.swift
//  Reader for Language Learner
//
//  Single source of truth for all visual tokens: colors, typography, spacing, radius.
//  Usage: DS.Color.surface, DS.Typography.body, DS.Spacing.md, DS.Radius.md
//

import AppKit
import SwiftUI

// MARK: - Design System Namespace

enum DS {

    // MARK: - Colors

    enum Color {
        // ── Surfaces ──────────────────────────────────────────────────────
        /// Primary window / panel background (adapts to light/dark)
        static var surface: SwiftUI.Color {
            SwiftUI.Color(nsColor: .windowBackgroundColor)
        }

        /// Slightly elevated surface: cards, input backgrounds
        static var surfaceElevated: SwiftUI.Color {
            SwiftUI.Color(nsColor: .controlBackgroundColor)
        }

        /// Deeply sunken inset areas
        static var surfaceInset: SwiftUI.Color {
            SwiftUI.Color(nsColor: .textBackgroundColor)
        }

        /// Hover state overlay
        static var hoverOverlay: SwiftUI.Color {
            SwiftUI.Color.primary.opacity(0.05)
        }

        // ── Text ──────────────────────────────────────────────────────────
        static var textPrimary:   SwiftUI.Color { .primary }
        static var textSecondary: SwiftUI.Color { .secondary }
        static var textTertiary:  SwiftUI.Color { SwiftUI.Color.primary.opacity(0.35) }
        static var textDisabled:  SwiftUI.Color { SwiftUI.Color.primary.opacity(0.22) }

        // ── Accent ────────────────────────────────────────────────────────
        /// Resolves the user's stored accent choice; `.system` falls back to
        /// `.accentColor` (the asset entry is intentionally empty, so that is
        /// the macOS system accent). Static computed props re-read the store
        /// on every body evaluation — the scene-root `AccentTintModifier`'s
        /// @AppStorage observation is what triggers those re-evaluations.
        static var accent:       SwiftUI.Color { AccentChoice.current.resolvedColor }
        static var accentSubtle: SwiftUI.Color { accent.opacity(0.10) }
        static var accentMuted:  SwiftUI.Color { accent.opacity(0.28) }
        static var accentStrong: SwiftUI.Color { accent.opacity(0.85) }

        // ── Semantic ──────────────────────────────────────────────────────
        static var success: SwiftUI.Color { .green }
        static var warning: SwiftUI.Color { .orange }
        static var danger:  SwiftUI.Color { .red }
        /// Soft warning wash for inline banners (LLM connection notice) —
        /// the warning-family sibling of `accentSubtle`.
        static var warningSubtle: SwiftUI.Color { warning.opacity(0.12) }
        /// The saved-word star. One token instead of `.yellow` hand-picked
        /// at every call site, so "saved" reads as one color everywhere.
        static var star: SwiftUI.Color { .yellow }

        // ── Identity palette extras ───────────────────────────────────────
        // The module/domain rainbow mostly rides system colors; these two are
        // the hues the system palette lacks. Defined here so no raw
        // `Color(hue:)` literal lives outside the design system.
        /// Warm bookish brown — etymology module, legal domain.
        static var brown: SwiftUI.Color { SwiftUI.Color(hue: 0.08, saturation: 0.55, brightness: 0.52) }
        /// Amber — usage-notes module; reads between `warning` and `star`.
        static var amber: SwiftUI.Color { SwiftUI.Color(hue: 0.12, saturation: 0.80, brightness: 0.78) }

        // ── Structural ────────────────────────────────────────────────────
        static var separator: SwiftUI.Color {
            SwiftUI.Color(nsColor: .separatorColor)
        }

        /// Single hairline stroke used for every panel / card border in the
        /// inspector. Replaces the ad-hoc `separator.opacity(0.06…0.45)` values
        /// so the whole surface reads as one system.
        static var hairline: SwiftUI.Color { separator.opacity(0.18) }

        /// Emphasized hairline for borders that must read against busy content
        /// (card faces, chart grid lines, swatch rings). Second and final step
        /// of the separator scale — anything stronger uses `separator` itself.
        static var hairlineStrong: SwiftUI.Color { separator.opacity(0.4) }

        // ── Surface scale ───────────────────────────────────────────────────
        // Three fixed levels so panels/cards stop each inventing their own
        // opacity. `panel` = outer container, `cardInset` = sunken content
        // (result body), `cardSoft` = gently raised item cards.
        static var panel:     SwiftUI.Color { surface.opacity(0.72) }
        static var cardInset: SwiftUI.Color { surfaceInset.opacity(0.96) }
        static var cardSoft:  SwiftUI.Color { surfaceElevated.opacity(0.60) }
    }

    // MARK: - Typography

    enum Typography {
        // Titles
        static var largeTitle: SwiftUI.Font { .largeTitle.weight(.bold) }
        static var title:      SwiftUI.Font { .title2.weight(.semibold) }
        static var headline:   SwiftUI.Font { .headline }

        // Body
        static var body:     SwiftUI.Font { .body }
        static var callout:  SwiftUI.Font { .callout }
        static var subhead:  SwiftUI.Font { .subheadline }

        // Small
        static var caption:  SwiftUI.Font { .caption }
        static var caption2: SwiftUI.Font { .caption2 }

        // Special
        static var label:    SwiftUI.Font { .subheadline.weight(.medium) }
        static var overline: SwiftUI.Font { .caption2.weight(.heavy) }
        static var mono:     SwiftUI.Font { .system(.caption, design: .monospaced) }

        /// A saved word's term, shown large — flashcards, word cards.
        static var wordDisplay:      SwiftUI.Font { .system(size: 22, weight: .semibold) }
        /// The larger variant — the flashcard front, the single most
        /// prominent term on screen.
        static var wordDisplayLarge: SwiftUI.Font { .system(size: 28, weight: .semibold) }

        /// Numeric display with tabular/rounded digits — ring percentages,
        /// stat counters, quiz results. Always `.rounded`; size varies by
        /// context, so this stays a function rather than a fixed constant.
        static func statNumber(_ size: CGFloat, weight: SwiftUI.Font.Weight = .bold) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .rounded)
        }

        /// Tiny UI chrome text — sidebar tab labels, count badges, chart
        /// axis ticks. Deliberately fixed-size, not a Dynamic Type role:
        /// these sit in space-constrained chrome, not body content.
        static func micro(_ size: CGFloat = 9, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            .system(size: size, weight: weight)
        }

        /// `Image(systemName:)` glyph sizing. Icons don't benefit from Dynamic
        /// Type the way text does, so this stays a plain size+weight wrapper —
        /// its job is centralizing the app's ~60 icon call sites into one
        /// declaration, not making them scale. Distinct from `micro`, which is
        /// for small fixed-size *text* chrome, not icon glyphs.
        static func icon(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            .system(size: size, weight: weight)
        }

        /// Large light-weight icon in a circular accent badge — the shared
        /// empty-state hero glyph (`DSEmptyState`, the dashboard's own
        /// "continue reading" hero). A literal duplicate of two call sites,
        /// not a catch-all for every big icon: other hero-sized icons
        /// (flashcard results, module empty states) are genuinely different
        /// sizes per context and stay as `icon(_:weight:)` calls.
        static var iconHero: SwiftUI.Font { .system(size: 30, weight: .light) }
    }

    // MARK: - Spacing

    enum Spacing {
        static let xxs: CGFloat =  2
        static let xs:  CGFloat =  4
        static let sm:  CGFloat =  8
        static let md:  CGFloat = 12
        static let lg:  CGFloat = 16
        static let xl:  CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 48
    }

    // MARK: - Corner Radius

    enum Radius {
        static let xs: CGFloat =  4
        static let sm: CGFloat =  6
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
        static let xl: CGFloat = 20
    }

    // MARK: - Animation

    enum Animation {
        static var standard:   SwiftUI.Animation { .easeInOut(duration: 0.2) }
        static var fast:       SwiftUI.Animation { .easeInOut(duration: 0.12) }
        static var spring:     SwiftUI.Animation { .spring(duration: 0.3, bounce: 0.2) }
        static var springFast: SwiftUI.Animation { .spring(duration: 0.22, bounce: 0.15) }
        static var snappy:     SwiftUI.Animation { .spring(duration: 0.18, bounce: 0.0) }
        /// The quiz flashcard's 3D flip — deliberately a touch longer than
        /// `standard` so the gesture reads with some weight.
        static var cardFlip:   SwiftUI.Animation { .easeInOut(duration: 0.25) }
        /// Continuous breathing pulse for live-status indicators (e.g. the
        /// LLM connection dot). The only repeating token — everything else
        /// in this enum is a one-shot transition curve.
        static var pulse:      SwiftUI.Animation { .easeInOut(duration: 0.6).repeatForever(autoreverses: true) }

        /// `base`, or a near-instant animation when Reduce Motion is on.
        /// `Animation` has no environment access of its own, so callers pass
        /// `\.accessibilityReduceMotion` from their own environment.
        static func respecting(_ base: SwiftUI.Animation, reduceMotion: Bool) -> SwiftUI.Animation? {
            reduceMotion ? nil : base
        }
    }

    // MARK: - Gradients

    /// The app's only gradients — exactly three call sites (dashboard hero
    /// wash, goal ring, stats chart fade). Anything else stays flat; a new
    /// gradient is a design decision, not a garnish.
    enum Gradient {
        /// Subtle accent wash for a card face — barely-there, top-leading in.
        static var accentWash: LinearGradient {
            LinearGradient(
                colors: [DS.Color.accent.opacity(0.14), DS.Color.accent.opacity(0.04)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }

        /// Angular sweep for the daily-goal progress ring.
        static var goalRing: AngularGradient {
            AngularGradient(
                colors: [DS.Color.accent.opacity(0.55), DS.Color.accent],
                center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)
            )
        }

        /// Vertical fade for chart area fills — accent into clear.
        static var chartFade: LinearGradient {
            LinearGradient(
                colors: [DS.Color.accent.opacity(0.22), DS.Color.accent.opacity(0.02)],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    // MARK: - Transitions

    /// A directional slide+fade, or a plain fade when Reduce Motion is on —
    /// same environment-forwarding rationale as `Animation.respecting`.
    static func slideTransition(edge: Edge, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity)
    }

    // MARK: - Shadow

    struct ShadowStyle {
        let color: SwiftUI.Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }

    enum Shadow {
        static let subtle = ShadowStyle(color: .black.opacity(0.07), radius: 3,  x: 0, y: 1)
        static let card   = ShadowStyle(color: .black.opacity(0.10), radius: 8,  x: 0, y: 3)
        static let float  = ShadowStyle(color: .black.opacity(0.14), radius: 16, x: 0, y: 6)
    }

    // MARK: - Layout

    enum Layout {
        static let sidebarDefault:   CGFloat = 260
        static let sidebarMin:       CGFloat = 200
        static let sidebarMax:       CGFloat = 380
        static let inspectorDefault: CGFloat = 420
        static let inspectorMin:     CGFloat = 320
        static let inspectorMax:     CGFloat = 600
        static let pdfMin:           CGFloat = 420
        static let windowMin     = CGSize(width: 900,  height: 600)
        static let windowDefault = CGSize(width: 1200, height: 800)

        /// One fixed size for every Settings tab — sized to the tallest
        /// (Prompts, 520pt) so switching tabs doesn't resize the window.
        static let settingsWindow = CGSize(width: 540, height: 520)

        // Thumbnail strip sizes (width; height is 4:3 ratio)
        static let thumbnailSmall:  CGFloat = 80
        static let thumbnailMedium: CGFloat = 120
        static let thumbnailLarge:  CGFloat = 160

        // Dashboard / Library content columns (EmptyStateView).
        static let dashboardContentWidth: CGFloat = 640
        static let libraryContentWidth:   CGFloat = 880

        // Document cover thumbnails (EmptyStateView, LibraryView).
        static let coverHero = CGSize(width: 52, height: 68)
        static let coverMini = CGSize(width: 22, height: 28)

        /// Quick Lookup HUD panel width.
        static let hudWidth: CGFloat = 420

        // QuizView card body heights — the flashcard front's minimum, and
        // the back/reveal scroll area's two size tiers (compact vs. the
        // flashcard back, which has more room to spare).
        static let cardFrontMinHeight: CGFloat = 160
        static let cardBackHeightCompact:  CGFloat = 220
        static let cardBackHeightExpanded: CGFloat = 300
    }

    enum ThumbnailSize: String, CaseIterable, Identifiable {
        case small  = "S"
        case medium = "M"
        case large  = "L"
        var id: String { rawValue }

        var width: CGFloat {
            switch self {
            case .small:  return DS.Layout.thumbnailSmall
            case .medium: return DS.Layout.thumbnailMedium
            case .large:  return DS.Layout.thumbnailLarge
            }
        }
        var height: CGFloat { width * 1.35 }
    }
}

// MARK: - Card Stroke

extension DS {
    /// Border options for `dsCard` — the two hairline steps plus none.
    enum CardStroke {
        case hairline
        case hairlineStrong
        case none

        var color: SwiftUI.Color? {
            switch self {
            case .hairline: return DS.Color.hairline
            case .hairlineStrong: return DS.Color.hairlineStrong
            case .none: return nil
            }
        }

        var lineWidth: CGFloat { 1 }
    }
}

/// `shadow(color:radius:)` with no shadow still costs a render pass — skip
/// the modifier entirely when the card has none.
private struct OptionalShadowModifier: ViewModifier {
    let style: DS.ShadowStyle?

    func body(content: Content) -> some View {
        if let style {
            content.dsShadow(style)
        } else {
            content
        }
    }
}

// MARK: - View Extensions

extension View {
    func dsShadow(_ style: DS.ShadowStyle) -> some View {
        shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }

    func dsOverlineLabel() -> some View {
        self
            .font(DS.Typography.overline)
            .foregroundStyle(DS.Color.textTertiary)
    }

    /// The app's one card chrome: surface + rounded corner + hairline stroke
    /// (+ optional shadow). Covers the variants the hand-rolled sites had
    /// drifted into; genuinely bespoke chrome stays inline with a
    /// `// DS-exempt:` note.
    func dsCard(
        padding: CGFloat? = DS.Spacing.md,
        surface: SwiftUI.Color = DS.Color.surfaceElevated,
        radius: CGFloat = DS.Radius.md,
        stroke: DS.CardStroke = .hairline,
        shadow: DS.ShadowStyle? = nil
    ) -> some View {
        self
            .padding(.all, padding ?? 0)
            .background(surface)
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay {
                if let strokeColor = stroke.color {
                    RoundedRectangle(cornerRadius: radius)
                        .strokeBorder(strokeColor, lineWidth: stroke.lineWidth)
                }
            }
            .modifier(OptionalShadowModifier(style: shadow))
    }

    /// Standard inspector container: a `panel` surface with a rounded corner and
    /// a single hairline border. Callers manage their own padding.
    func dsPanel(
        surface: SwiftUI.Color = DS.Color.panel,
        cornerRadius: CGFloat = DS.Radius.lg
    ) -> some View {
        self
            .background(surface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(DS.Color.hairline, lineWidth: 0.6)
            )
    }
}

// MARK: - Section Header

/// Overline section label with an optional trailing accessory (e.g. a "Run All"
/// action). Anchors visual hierarchy between the inspector's zones.
struct DSSectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: DS.Spacing.sm) {
            Text(title.uppercased())
                .dsOverlineLabel()
            Spacer(minLength: DS.Spacing.sm)
            trailing()
        }
    }
}

// MARK: - EmptyStateView

/// A reusable empty-state component used throughout the app.
/// Replaces ad-hoc VStack-with-icon patterns in every view.
struct DSEmptyState: View {
    let icon: String
    /// `LocalizedStringKey`, not `String` — a `Text(String)` call silently
    /// skips the string catalog (see CLAUDE.md), and every call site here is
    /// static app copy, so literals resolve through the catalog for free.
    let title: LocalizedStringKey
    let message: LocalizedStringKey?
    var action: (() -> Void)? = nil
    var actionLabel: LocalizedStringKey? = nil

    var body: some View {
        VStack(spacing: DS.Spacing.lg) {
            Spacer()

            ZStack {
                Circle()
                    .fill(DS.Color.accentSubtle)
                    .frame(width: 72, height: 72)
                Image(systemName: icon)
                    .font(DS.Typography.iconHero)
                    .foregroundStyle(DS.Color.accent)
            }

            VStack(spacing: DS.Spacing.xs) {
                Text(title)
                    .font(DS.Typography.headline)
                    .foregroundStyle(DS.Color.textPrimary)
                if let message {
                    Text(message)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
            }

            if let action, let actionLabel {
                Button(actionLabel, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - DSToast

/// Lightweight capsule toast for transient feedback ("Copied!", "Saved!", etc.)
struct DSToast: View {

    enum Variant {
        case success, info, warning

        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .info:    return "info.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            }
        }
        var color: SwiftUI.Color {
            switch self {
            case .success: return DS.Color.success
            case .info:    return DS.Color.accent
            case .warning: return DS.Color.warning
            }
        }
    }

    let message: String
    var variant: Variant = .success

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: variant.icon)
                .foregroundStyle(variant.color)
            Text(message)
                .font(DS.Typography.subhead)
                .foregroundStyle(DS.Color.textPrimary)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
        .background(.regularMaterial, in: Capsule())
        .dsShadow(DS.Shadow.float)
    }
}

private struct DSToastModifier: ViewModifier {
    @Binding var isPresented: Bool
    let message: String
    var variant: DSToast.Variant
    var duration: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if isPresented {
                DSToast(message: message, variant: variant)
                    .padding(.top, DS.Spacing.xl)
                    .transition(DS.slideTransition(edge: .top, reduceMotion: reduceMotion))
                    .task(id: message) {
                        try? await Task.sleep(for: .seconds(duration))
                        withAnimation(DS.Animation.respecting(DS.Animation.standard, reduceMotion: reduceMotion)) {
                            isPresented = false
                        }
                    }
                    .zIndex(999)
                    .allowsHitTesting(false)
            }
        }
        .animation(DS.Animation.respecting(DS.Animation.spring, reduceMotion: reduceMotion), value: isPresented)
    }
}

extension View {
    /// Overlays a self-dismissing toast banner at the top of this view.
    func dsToast(
        isPresented: Binding<Bool>,
        message: String,
        variant: DSToast.Variant = .success,
        duration: Double = 1.5
    ) -> some View {
        modifier(DSToastModifier(
            isPresented: isPresented,
            message: message,
            variant: variant,
            duration: duration
        ))
    }
}

// MARK: - DSProgressBar

/// The thin reading-progress bar — one drawing for the dashboard hero, the
/// library card overlay, and the stats sheet, which had each invented their
/// own track/fill opacities.
struct DSProgressBar: View {
    /// 0…1.
    let value: Double
    var height: CGFloat = 3
    /// Track color; the default suits app surfaces. Over full-color cover
    /// art pass a dimming track (see LibraryCard) so the bar stays legible.
    var track: SwiftUI.Color = DS.Color.accentSubtle

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(track)
                Rectangle()
                    .fill(DS.Color.accentStrong)
                    .frame(width: geo.size.width * min(1, max(0, value)))
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel(Text("Reading progress"))
        .accessibilityValue(Text("\(Int(min(1, max(0, value)) * 100))%"))
    }
}

// MARK: - DSCoverPlaceholder

/// Placeholder for a document cover that hasn't rendered (or can't) — one
/// look shared by the dashboard hero, recents rows, and the library grid.
struct DSCoverPlaceholder: View {
    /// Roughly the placeholder's shorter dimension; drives the glyph size.
    var iconSize: CGFloat = 16
    /// False = the document file is missing; shows the broken-file glyph.
    var fileExists: Bool = true

    var body: some View {
        ZStack {
            DS.Color.accentSubtle
            Image(systemName: fileExists ? "book.pages" : "questionmark.folder")
                .font(DS.Typography.icon(iconSize, weight: .light))
                .foregroundStyle(DS.Color.accent.opacity(0.7))
        }
    }
}

// MARK: - VisualEffectView (NSVisualEffectView wrapper)

/// Provides native macOS blur / vibrancy effects.
/// Use `.sidebar` material for the native sidebar appearance.
struct VisualEffectView: NSViewRepresentable {
    var material:     NSVisualEffectView.Material     = .sidebar
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material     = material
        view.blendingMode = blendingMode
        view.state        = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material     = material
        nsView.blendingMode = blendingMode
    }
}
