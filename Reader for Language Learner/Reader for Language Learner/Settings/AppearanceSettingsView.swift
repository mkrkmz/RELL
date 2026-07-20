//
//  AppearanceSettingsView.swift
//  Reader for Language Learner
//
//  Default page theme and panel width preferences.
//

import SwiftUI

struct AppearanceSettingsView: View {

    // NOTE: this grid used to write the orphaned key "defaultPageTheme"
    // while the reader read "pageTheme" — the Settings picker never had any
    // effect. Rebound to the live key; the orphan is silently ignored (it
    // never influenced anything, so there is nothing worth migrating).
    @AppStorage("pageTheme") private var pageThemeRaw = PageTheme.original.rawValue
    @AppStorage("appTheme")  private var appThemeRaw = AppTheme.system.rawValue
    @AppStorage(AccentChoice.storageKey) private var accentRaw = AccentChoice.system.rawValue
    @AppStorage("inspectorWidth")   private var inspectorWidth: Double = Double(DS.Layout.inspectorDefault)
    @AppStorage("sidebarWidth")     private var sidebarWidth:   Double = Double(DS.Layout.sidebarDefault)

    private var appTheme: AppTheme { AppTheme(rawValue: appThemeRaw) ?? .system }
    private var accent: AccentChoice { AccentChoice(rawValue: accentRaw) ?? .system }

    var body: some View {
        Form {
            Section("App Theme") {
                Picker("Appearance", selection: $appThemeRaw) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.localizedTitle).tag(theme.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                accentRow
            }

            Section("Page Theme") {
                pageThemeGrid
            }

            Section("Panel Widths") {
                panelWidthRow(
                    label: "Inspector",
                    value: $inspectorWidth,
                    range: Double(DS.Layout.inspectorMin)...Double(DS.Layout.inspectorMax),
                    defaultValue: Double(DS.Layout.inspectorDefault)
                )
                panelWidthRow(
                    label: "Sidebar",
                    value: $sidebarWidth,
                    range: Double(DS.Layout.sidebarMin)...Double(DS.Layout.sidebarMax),
                    defaultValue: Double(DS.Layout.sidebarDefault)
                )
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Accent Color

    private var accentRow: some View {
        LabeledContent("Accent Color") {
            HStack(spacing: DS.Spacing.sm) {
                ForEach(AccentChoice.allCases) { choice in
                    accentSwatch(choice)
                }
            }
        }
    }

    private func accentSwatch(_ choice: AccentChoice) -> some View {
        let isSelected = choice == accent
        return Button {
            accentRaw = choice.rawValue
        } label: {
            ZStack {
                if let color = choice.color {
                    Circle().fill(color)
                } else {
                    // "System" — half-split swatch, no single color to show.
                    Circle().fill(
                        AngularGradient(
                            colors: [.accentColor, Color(nsColor: .systemGray)],
                            center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)
                        )
                    )
                }
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(DS.Typography.icon(9, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 22, height: 22)
            .overlay {
                Circle().strokeBorder(
                    isSelected ? DS.Color.textPrimary.opacity(0.5) : DS.Color.hairlineStrong,
                    lineWidth: isSelected ? 1.5 : 1
                )
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(choice.localizedTitle)
        .accessibilityLabel(choice.localizedTitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(DS.Animation.springFast, value: isSelected)
    }

    // MARK: - Page Theme Grid

    private var pageThemeGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.sm), count: 3),
            spacing: DS.Spacing.sm
        ) {
            ForEach(PageTheme.allCases) { theme in
                pageThemeCard(theme)
            }
        }
        .padding(.vertical, DS.Spacing.sm)
    }

    private func pageThemeCard(_ theme: PageTheme) -> some View {
        let isSelected = pageThemeRaw == theme.rawValue
        return Button {
            pageThemeRaw = theme.rawValue
        } label: {
            VStack(spacing: DS.Spacing.sm) {
                // Colour swatch
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .fill(Color(nsColor: theme.backgroundColor))
                    .frame(height: 44)
                    .overlay {
                        RoundedRectangle(cornerRadius: DS.Radius.sm)
                            .stroke(
                                isSelected ? DS.Color.accent : DS.Color.textTertiary.opacity(0.25),
                                lineWidth: isSelected ? 2 : 1
                            )
                    }
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(DS.Color.accent)
                                .padding(4)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }

                VStack(spacing: 1) {
                    Image(systemName: theme.iconName)
                        .font(.caption)
                        .foregroundStyle(isSelected ? DS.Color.accent : DS.Color.textSecondary)
                    Text(theme.localizedTitle)
                        .font(DS.Typography.caption2)
                        .foregroundStyle(isSelected ? DS.Color.accent : DS.Color.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        }
        .buttonStyle(.plain)
        .animation(DS.Animation.springFast, value: isSelected)
    }

    // MARK: - Panel Width Row

    private func panelWidthRow(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        defaultValue: Double
    ) -> some View {
        LabeledContent(label) {
            HStack(spacing: DS.Spacing.sm) {
                Slider(value: value, in: range, step: 10)
                    .frame(width: 200)
                Text("\(Int(value.wrappedValue))px")
                    .font(DS.Typography.mono)
                    .foregroundStyle(DS.Color.textTertiary)
                    .frame(width: 44, alignment: .trailing)
                Button {
                    value.wrappedValue = defaultValue
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .foregroundStyle(DS.Color.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Reset to default")
            }
        }
    }
}

#Preview {
    AppearanceSettingsView()
}
