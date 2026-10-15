//
//  DSButtonStyles.swift
//  Reader for Language Learner
//
//  The button family (Roadmap v18 Sprint 1, approved mockup): quiet, icon
//  and chip here; primary and secondary are the system's `.borderedProminent`
//  and `.bordered`. One hover rule for all of them — a light wash under the
//  pointer, a little more while pressed, `DS.Animation.fast`, no animation
//  with Reduce Motion — and a dimmed look when disabled. A screen has at most
//  one primary button, for the step that moves on (Start Test, Download,
//  Continue); actions in a row — Save, Listen, Anki — are quiet.
//

import SwiftUI

extension DS {
    /// Hover and press washes, light and dark (approved: 6 % / 8 %, 11 %).
    enum Interaction {
        static func wash(hovering: Bool, pressed: Bool, dark: Bool) -> SwiftUI.Color {
            if pressed { return SwiftUI.Color.primary.opacity(dark ? 0.14 : 0.11) }
            if hovering { return SwiftUI.Color.primary.opacity(dark ? 0.08 : 0.06) }
            return .clear
        }

        /// What a disabled control fades to.
        static let disabledOpacity: Double = 0.38
    }
}

// MARK: - Quiet

/// No fill: the icon in `tint`, the label in the text colour, a wash under
/// the pointer. `isOn` (the Inspector card's open module, v18 S2): a light
/// fill and the label in `tint` too. Use with `Label` or a plain title.
struct DSQuietButtonStyle: ButtonStyle {
    var isOn = false
    var tint: SwiftUI.Color = DS.Color.accent

    func makeBody(configuration: Configuration) -> some View {
        DSWashedButton(configuration: configuration, shape: Capsule()) { label in
            label
                .labelStyle(DSQuietLabelStyle(tint: tint))
                .font(DS.Typography.caption.weight(.semibold))
                .foregroundStyle(isOn ? tint : DS.Color.textPrimary)
                .padding(.horizontal, DS.Spacing.sm + DS.Spacing.xxs)
                .frame(minHeight: 26)
                .background(isOn ? tint.opacity(0.14) : .clear, in: Capsule())
        }
    }
}

/// Icon in `tint`, title in the text colour.
struct DSQuietLabelStyle: LabelStyle {
    var tint: SwiftUI.Color = DS.Color.accent

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            configuration.icon
                .font(DS.Typography.icon(12, weight: .semibold))
                .foregroundStyle(tint)
            configuration.title
        }
    }
}

// MARK: - Icon

/// An icon alone, in a square that washes under the pointer. Give it a
/// `.help` and an `.accessibilityLabel` — there's no title to read.
struct DSIconButtonStyle: ButtonStyle {
    var tint: SwiftUI.Color = DS.Color.accent

    func makeBody(configuration: Configuration) -> some View {
        DSWashedButton(configuration: configuration, shape: RoundedRectangle(cornerRadius: DS.Radius.sm)) { label in
            label
                .labelStyle(.iconOnly)
                .font(DS.Typography.icon(12, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
        }
    }
}

// MARK: - Chip

/// A choice among several: on, a light fill and text in `tint`; off, a
/// hairline and secondary text. `tile`: a rounded square whose label sets
/// its own size and colours (the Inspector's module tiles).
struct DSChipButtonStyle: ButtonStyle {
    var isOn: Bool
    var tint: SwiftUI.Color = DS.Color.accent
    var tile = false

    func makeBody(configuration: Configuration) -> some View {
        if tile {
            DSWashedButton(configuration: configuration, shape: RoundedRectangle(cornerRadius: DS.Radius.sm)) { label in
                label
                    .background(isOn ? tint.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: DS.Radius.sm))
                    .overlay { DSChipOutline(isOn: isOn, shape: RoundedRectangle(cornerRadius: DS.Radius.sm)) }
            }
        } else {
            DSWashedButton(configuration: configuration, shape: Capsule()) { label in
                label
                    .font(DS.Typography.caption.weight(isOn ? .semibold : .medium))
                    .foregroundStyle(isOn ? tint : DS.Color.textSecondary)
                    .padding(.horizontal, DS.Spacing.sm + DS.Spacing.xxs)
                    .frame(minHeight: 24)
                    .background(isOn ? tint.opacity(0.12) : .clear, in: Capsule())
                    .overlay { DSChipOutline(isOn: isOn, shape: Capsule()) }
            }
        }
    }
}

/// The hairline around a chip that isn't on.
private struct DSChipOutline<S: InsettableShape>: View {
    let isOn: Bool
    let shape: S

    var body: some View {
        if !isOn { shape.strokeBorder(SwiftUI.Color.primary.opacity(0.14), lineWidth: 0.8) }
    }
}

// MARK: - Shared hover / press / disabled

/// The one hover rule, shared by every style above.
struct DSWashedButton<S: Shape, Content: View>: View {
    let configuration: ButtonStyleConfiguration
    let shape: S
    @ViewBuilder let content: (ButtonStyleConfiguration.Label) -> Content

    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content(configuration.label)
            .background(
                DS.Interaction.wash(hovering: hovering && isEnabled, pressed: configuration.isPressed,
                                    dark: colorScheme == .dark),
                in: shape
            )
            .contentShape(shape)
            .opacity(isEnabled ? 1 : DS.Interaction.disabledOpacity)
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : DS.Animation.fast, value: hovering)
            .animation(reduceMotion ? nil : DS.Animation.fast, value: configuration.isPressed)
    }
}

// MARK: - Shorthands

extension ButtonStyle where Self == DSQuietButtonStyle {
    /// Save, Listen, Anki and other actions in a row.
    static var dsQuiet: DSQuietButtonStyle { DSQuietButtonStyle() }
    /// A quiet button that can be on (the card's open module).
    static func dsQuiet(isOn: Bool, tint: SwiftUI.Color = DS.Color.accent) -> DSQuietButtonStyle {
        DSQuietButtonStyle(isOn: isOn, tint: tint)
    }
}

extension ButtonStyle where Self == DSIconButtonStyle {
    /// Refresh, copy, close — an icon alone.
    static var dsIcon: DSIconButtonStyle { DSIconButtonStyle() }
    /// An icon alone in a quieter colour (close, dismiss).
    static var dsIconSecondary: DSIconButtonStyle { DSIconButtonStyle(tint: DS.Color.textSecondary) }
}

extension ButtonStyle where Self == DSChipButtonStyle {
    static func dsChip(isOn: Bool, tint: SwiftUI.Color = DS.Color.accent) -> DSChipButtonStyle {
        DSChipButtonStyle(isOn: isOn, tint: tint)
    }
    /// A chip that is a rounded square with its own content (icon over title).
    static func dsChipTile(isOn: Bool, tint: SwiftUI.Color = DS.Color.accent) -> DSChipButtonStyle {
        DSChipButtonStyle(isOn: isOn, tint: tint, tile: true)
    }
}
