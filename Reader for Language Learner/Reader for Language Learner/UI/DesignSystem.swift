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

        // Thumbnail strip sizes (width; height is 4:3 ratio)
        static let thumbnailSmall:  CGFloat = 80
        static let thumbnailMedium: CGFloat = 120
        static let thumbnailLarge:  CGFloat = 160
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
}

// MARK: - EmptyStateView

/// A reusable empty-state component used throughout the app.
/// Replaces ad-hoc VStack-with-icon patterns in every view.
struct DSEmptyState: View {
    let icon: String
    let title: String
    let message: String?
    var action: (() -> Void)? = nil
    var actionLabel: String? = nil

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

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if isPresented {
                DSToast(message: message, variant: variant)
                    .padding(.top, DS.Spacing.xl)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: message) {
                        try? await Task.sleep(for: .seconds(duration))
                        withAnimation(DS.Animation.standard) { isPresented = false }
                    }
                    .zIndex(999)
                    .allowsHitTesting(false)
            }
        }
        .animation(DS.Animation.spring, value: isPresented)
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
