//
//  AppearanceSettingsView.swift
//  Reader for Language Learner
//
//  Default page theme and panel width preferences.
//

import SwiftUI

struct AppearanceSettingsView: View {

    @AppStorage("defaultPageTheme") private var pageThemeRaw = PageTheme.original.rawValue
    @AppStorage("inspectorWidth")   private var inspectorWidth: Double = Double(DS.Layout.inspectorDefault)
    @AppStorage("sidebarWidth")     private var sidebarWidth:   Double = Double(DS.Layout.sidebarDefault)

    var body: some View {
        Form {
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
        .frame(width: 540, height: 340)
    }

    // MARK: - Page Theme Grid

    private var pageThemeGrid: some View {
        HStack(spacing: DS.Spacing.sm) {
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
                    Text(theme.displayName)
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
