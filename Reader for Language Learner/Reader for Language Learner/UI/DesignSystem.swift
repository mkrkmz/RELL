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
        static var accent:       SwiftUI.Color { .accentColor }
        static var accentSubtle: SwiftUI.Color { .accentColor.opacity(0.10) }
        static var accentMuted:  SwiftUI.Color { .accentColor.opacity(0.28) }
        static var accentStrong: SwiftUI.Color { .accentColor.opacity(0.85) }

        // ── Semantic ──────────────────────────────────────────────────────
        static var success: SwiftUI.Color { .green }
        static var warning: SwiftUI.Color { .orange }
        static var danger:  SwiftUI.Color { .red }

        // ── Structural ────────────────────────────────────────────────────
        static var separator: SwiftUI.Color {
            SwiftUI.Color(nsColor: .separatorColor)
        }

        /// Single hairline stroke used for every panel / card border in the
        /// inspector. Replaces the ad-hoc `separator.opacity(0.06…0.45)` values
        /// so the whole surface reads as one system.
        static var hairline: SwiftUI.Color { separator.opacity(0.18) }

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

    func dsCard(padding: CGFloat = DS.Spacing.md) -> some View {
        self
            .padding(padding)
            .background(DS.Color.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
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
                    .font(.system(size: 30, weight: .light))
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
