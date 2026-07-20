//
//  ReadingAppearanceView.swift
//  Reader for Language Learner
//
//  The toolbar "Aa" popover: page-theme swatches for both formats, plus
//  EPUB-only reading typography (font family, size, line height, column
//  width, justification). Everything binds to the same global @AppStorage
//  keys the menu bar and reader already use, so the popover, the View menu,
//  and ⌘+/⌘− all stay in sync for free.
//

import SwiftUI

struct ReadingAppearanceView: View {
    /// EPUB shows the typography controls; PDF gets a hint instead
    /// (fixed layout — only the theme applies).
    let isEPUB: Bool

    @AppStorage("pageTheme") private var pageThemeRaw = PageTheme.original.rawValue
    @AppStorage("epubFontSize") private var epubFontSize: Double = 18
    @AppStorage(EPUBTypography.lineHeightKey) private var epubLineHeight: Double = 1.6
    @AppStorage(EPUBFontFamily.storageKey) private var epubFontFamilyRaw = EPUBFontFamily.publisher.rawValue
    @AppStorage(EPUBContentWidth.storageKey) private var epubContentWidthRaw = EPUBContentWidth.medium.rawValue
    @AppStorage(EPUBTypography.justifiedKey) private var epubJustified = false

    private var pageTheme: PageTheme { PageTheme(rawValue: pageThemeRaw) ?? .original }
    private var fontFamily: EPUBFontFamily { EPUBFontFamily(rawValue: epubFontFamilyRaw) ?? .publisher }
    private var contentWidth: EPUBContentWidth { EPUBContentWidth(rawValue: epubContentWidthRaw) ?? .medium }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("Page Theme")
                .font(DS.Typography.caption.weight(.semibold))
                .foregroundStyle(DS.Color.textSecondary)

            themeGrid

            if isEPUB {
                Divider()
                typographySection
            } else {
                Text("Typography controls apply to EPUB books.")
                    .font(DS.Typography.caption2)
                    .foregroundStyle(DS.Color.textTertiary)
            }
        }
        .padding(DS.Spacing.lg)
        .frame(width: 316)
    }

    // MARK: - Theme swatches

    private var themeGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.sm), count: 3),
                  spacing: DS.Spacing.sm) {
            ForEach(PageTheme.allCases) { theme in
                themeSwatch(theme)
            }
        }
    }

    private func themeSwatch(_ theme: PageTheme) -> some View {
        let isSelected = theme == pageTheme
        // The EPUB color pair doubles as the swatch preview; `.original`
        // has no override colors, so preview plain black-on-white.
        let background = Color(hex: theme.epubColors?.background ?? "#ffffff")
        let ink = Color(hex: theme.epubColors?.text ?? "#1d1d1f")
        return Button {
            pageThemeRaw = theme.rawValue
        } label: {
            VStack(spacing: DS.Spacing.xxs) {
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .fill(background)
                    .frame(height: 40)
                    .overlay {
                        Text(verbatim: "Aa")
                            .font(DS.Typography.callout.weight(.medium))
                            .foregroundStyle(ink)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: DS.Radius.sm)
                            .strokeBorder(
                                isSelected ? DS.Color.accent : DS.Color.hairlineStrong,
                                lineWidth: isSelected ? 2 : 1
                            )
                    }
                Text(theme.localizedTitle)
                    .font(DS.Typography.caption2)
                    .foregroundStyle(isSelected ? DS.Color.accent : DS.Color.textSecondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(DS.Animation.springFast, value: isSelected)
        .accessibilityLabel(theme.localizedTitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Typography (EPUB)

    private var typographySection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("Typography")
                .font(DS.Typography.caption.weight(.semibold))
                .foregroundStyle(DS.Color.textSecondary)

            LabeledContent {
                Picker("", selection: $epubFontFamilyRaw) {
                    ForEach(EPUBFontFamily.allCases) { family in
                        Text(family.localizedTitle).tag(family.rawValue)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 170)
            } label: {
                Text("Font")
                    .font(DS.Typography.caption)
            }

            LabeledContent {
                HStack(spacing: DS.Spacing.sm) {
                    Stepper(
                        value: $epubFontSize,
                        in: 12...28, step: 1
                    ) {
                        Text("\(Int(epubFontSize)) pt")
                            .font(DS.Typography.mono)
                            .frame(width: 42, alignment: .trailing)
                    }
                }
            } label: {
                Text("Size")
                    .font(DS.Typography.caption)
            }

            LabeledContent {
                HStack(spacing: DS.Spacing.sm) {
                    Slider(value: $epubLineHeight, in: 1.2...2.0, step: 0.1)
                        .frame(width: 130)
                    Text(String(format: "%.1f", epubLineHeight))
                        .font(DS.Typography.mono)
                        .foregroundStyle(DS.Color.textTertiary)
                        .frame(width: 28, alignment: .trailing)
                }
            } label: {
                Text("Line Height")
                    .font(DS.Typography.caption)
            }

            LabeledContent {
                Picker("", selection: $epubContentWidthRaw) {
                    ForEach(EPUBContentWidth.allCases) { width in
                        Text(width.localizedTitle).tag(width.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 190)
            } label: {
                Text("Width")
                    .font(DS.Typography.caption)
            }

            Toggle(isOn: $epubJustified) {
                Text("Justify Text")
                    .font(DS.Typography.caption)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            HStack {
                Spacer()
                Button("Reset Typography") {
                    epubFontSize = 18
                    epubLineHeight = 1.6
                    epubFontFamilyRaw = EPUBFontFamily.publisher.rawValue
                    epubContentWidthRaw = EPUBContentWidth.medium.rawValue
                    epubJustified = false
                }
                .controlSize(.small)
            }
        }
    }
}

// MARK: - Hex color helper

extension Color {
    /// Parses "#rrggbb" — used for the theme swatch previews, which share
    /// the EPUB CSS hex definitions so swatch and page can't drift apart.
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: String(hex.dropFirst())).scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }
}

#Preview("EPUB") {
    ReadingAppearanceView(isEPUB: true)
}

#Preview("PDF") {
    ReadingAppearanceView(isEPUB: false)
}
