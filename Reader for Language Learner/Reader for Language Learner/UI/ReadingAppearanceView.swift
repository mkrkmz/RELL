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

    @AppStorage(StorageKey.pageTheme) private var pageThemeRaw = PageTheme.original.rawValue
    @AppStorage(StorageKey.epubFontSize) private var epubFontSize: Double = 18
    @AppStorage(EPUBTypography.lineHeightKey) private var epubLineHeight: Double = 1.6
    @AppStorage(EPUBFontFamily.storageKey) private var epubFontFamilyRaw = EPUBFontFamily.publisher.rawValue
    @AppStorage(EPUBContentWidth.storageKey) private var epubContentWidthRaw = EPUBContentWidth.medium.rawValue
    @AppStorage(EPUBTypography.justifiedKey) private var epubJustified = false

    private var pageTheme: PageTheme { PageTheme(rawValue: pageThemeRaw) ?? .original }
    private var fontFamily: EPUBFontFamily { EPUBFontFamily(rawValue: epubFontFamilyRaw) ?? .publisher }

    // v18 S4 (approved mockup): the themes in one row, a sample line in the
    // chosen type, A− / A+, three line spacings, and a link to reset.
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("Page Theme")
                .font(DS.Typography.caption.weight(.semibold))
                .foregroundStyle(DS.Color.textSecondary)

            themeRow

            if isEPUB {
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

    private var themeRow: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(PageTheme.allCases) { theme in
                themeSwatch(theme)
                    .frame(maxWidth: .infinity)
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
                Circle()
                    .fill(background)
                    .frame(width: 32, height: 32)
                    .overlay {
                        Text(verbatim: "Aa")
                            .font(DS.Typography.caption.weight(.semibold))
                            .foregroundStyle(ink)
                    }
                    .overlay { Circle().strokeBorder(DS.Color.hairlineStrong, lineWidth: 1) }
                    .padding(DS.Spacing.xxs)
                    .overlay {
                        if isSelected { Circle().strokeBorder(DS.Color.accent, lineWidth: 2) }
                    }
                Text(theme.localizedTitle)
                    .font(DS.Typography.caption2.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? DS.Color.accent : DS.Color.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(DS.Animation.springFast, value: isSelected)
        .help(theme.localizedTitle)
        .accessibilityLabel(theme.localizedTitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Typography (EPUB)

    private var typographySection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            sample

            LabeledContent("Font") {
                Picker("Font", selection: $epubFontFamilyRaw) {
                    ForEach(EPUBFontFamily.allCases) { family in
                        Text(family.localizedTitle).tag(family.rawValue)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 170)
            }

            LabeledContent("Size") {
                HStack(spacing: DS.Spacing.sm) {
                    Button("Smaller", systemImage: "textformat.size.smaller") { stepFontSize(-1) }
                        .labelStyle(.iconOnly)
                        .disabled(epubFontSize <= EPUBTypography.minFontSize)
                    Text("\(Int(epubFontSize)) pt")
                        .font(DS.Typography.mono)
                        .monospacedDigit()
                        .frame(minWidth: 40)
                    Button("Larger", systemImage: "textformat.size.larger") { stepFontSize(1) }
                        .labelStyle(.iconOnly)
                        .disabled(epubFontSize >= EPUBTypography.maxFontSize)
                }
            }

            LabeledContent("Line Spacing") {
                Picker("Line Spacing", selection: Binding(
                    get: { EPUBLineSpacing.nearest(to: epubLineHeight) },
                    set: { epubLineHeight = $0.lineHeight }
                )) {
                    ForEach(EPUBLineSpacing.allCases) { Text($0.localizedTitle).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 190)
            }

            LabeledContent("Width") {
                Picker("Width", selection: $epubContentWidthRaw) {
                    ForEach(EPUBContentWidth.allCases) { width in
                        Text(width.localizedTitle).tag(width.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 190)
            }

            Toggle("Justify Text", isOn: $epubJustified)
                .toggleStyle(.switch)
                .controlSize(.mini)

            HStack {
                Spacer()
                Button("Restore Defaults") {
                    epubFontSize = EPUBTypography.defaultFontSize
                    epubLineHeight = EPUBLineSpacing.normal.lineHeight
                    epubFontFamilyRaw = EPUBFontFamily.publisher.rawValue
                    epubContentWidthRaw = EPUBContentWidth.medium.rawValue
                    epubJustified = false
                }
                .buttonStyle(.link)
                .font(DS.Typography.caption)
            }
        }
        .font(DS.Typography.caption)
    }

    /// A line in the chosen font, on the chosen page, so a change shows
    /// without looking past the panel.
    private var sample: some View {
        Text(verbatim: "She pulled her coat tighter and read the notice again.")
            .font(sampleFont)
            .lineSpacing(CGFloat(epubLineHeight - 1) * 15)
            .foregroundStyle(Color(hex: pageTheme.epubColors?.text ?? "#1d1d1f"))
            .padding(DS.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: pageTheme.epubColors?.background ?? "#ffffff"),
                        in: RoundedRectangle(cornerRadius: DS.Radius.sm))
            .overlay { RoundedRectangle(cornerRadius: DS.Radius.sm).strokeBorder(DS.Color.hairlineStrong, lineWidth: 1) }
            .accessibilityHidden(true)
    }

    private var sampleFont: Font {
        let size = min(max(epubFontSize, EPUBTypography.minFontSize), EPUBTypography.maxFontSize) * 0.8
        if let name = fontFamily.fontFamilyName { return .custom(name, size: size) }
        // DS-exempt: the sample is sized like the page, not a UI text style.
        return Font.system(size: size, design: fontFamily == .sanFrancisco ? .default : .serif)
    }

    private func stepFontSize(_ step: Double) {
        epubFontSize = min(max(epubFontSize + step, EPUBTypography.minFontSize), EPUBTypography.maxFontSize)
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
