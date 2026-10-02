//
//  InspectorView+Grid.swift
//  Reader for Language Learner
//
//  Explanations: four module chips and a "More" menu (v14 S2).
//

import SwiftUI

extension InspectorView {

    // MARK: - Explanations (module chips)

    /// v14 S2: the four modules used most as chips, the rest — with Run All —
    /// in a "More" menu that takes the place of a fifth chip. One row of a
    /// fixed count, so its height never depends on the column's width.
    var moduleGrid: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            DSSectionHeader(String(localized: "Explanations")) {
                detailPicker
            }
            .padding(.horizontal, DS.Spacing.xxs)

            DSGlassGroup(spacing: DS.Spacing.xxs) {
                HStack(spacing: DS.Spacing.xxs) {
                    ForEach(ModuleType.inspectorFront, id: \.self) { module in
                        moduleButton(for: module, shortcut: nil)
                    }
                    moreModulesMenu
                }
            }
            .padding(.horizontal, DS.Spacing.xxs)
        }
        .animation(DS.Animation.snappy, value: explainMode)
        // ⇧⌘R (Run All) keeps working with its menu closed.
        .background(runAllShortcutButton)
    }

    private var detailPicker: some View {
        Picker("Detail", selection: $explainDetail) {
            Text("Short").tag(ExplainDetail.short)
            Text("Detailed").tag(ExplainDetail.detailed)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.mini)
        .fixedSize()
        .help("How much the explanations say")
    }

    // MARK: - More (menu chip)

    /// Shows the module it holds when that one is open, so the active result
    /// always has a lit chip above it.
    private var moreModulesMenu: some View {
        let menuModules = ModuleType.inspectorMore
        let activeInMenu = activeModule.flatMap { menuModules.contains($0) ? $0 : nil }
        let hasOutput = menuModules.contains { module in
            !(viewModel.outputs[module] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        return Menu {
            ForEach(menuModules, id: \.self) { module in
                Button {
                    toggleModule(module)
                } label: {
                    Label(module.title(nativeLanguage: nativeLanguage), systemImage: module.iconName)
                }
                .disabled(!isModuleEnabled(module) && viewModel.loading[module] != true)
            }
            Divider()
            Button {
                runAllPrimaryModules()
            } label: {
                Label("Run All", systemImage: "play.fill")
            }
            .disabled(!hasSelection)
        } label: {
            VStack(spacing: DS.Spacing.xxs) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: activeInMenu?.iconName ?? "ellipsis")
                        .font(DS.Typography.icon(14, weight: .medium))
                        .frame(width: 18, height: 18)
                    if hasOutput && activeInMenu == nil {
                        statusDot(DS.Color.accent)
                    }
                }
                Text(activeInMenu?.shortTitle ?? String(localized: "More"))
                    .font(DS.Typography.caption2)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .foregroundStyle(activeInMenu.map { $0.accentColor } ?? DS.Color.textSecondary)
            .contentShape(Rectangle())
        }
        // .button + .plain draws the label as built (icon over title, like
        // the chips); .borderlessButton flattened it into one line.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .frame(maxWidth: .infinity)
        .dsGlassInteractive(
            cornerRadius: DS.Radius.sm,
            tint: nil,
            fallback: AnyShapeStyle(activeInMenu.map { $0.accentColor.opacity(0.12) } ?? DS.Color.surfaceInset),
            fallbackStroke: .none
        )
        .help("More explanations and Run All (⇧⌘R)")
        .accessibilityLabel("More explanations")
    }

    private var runAllShortcutButton: some View {
        Button { runAllPrimaryModules() } label: { Color.clear }
            .frame(width: 0, height: 0)
            .opacity(0)
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!hasSelection)
            .accessibilityHidden(true)
    }

    // MARK: - Module Button

    @ViewBuilder
    func moduleButton(
        for module: ModuleType,
        shortcut: KeyEquivalent?,
        compact: Bool = false
    ) -> some View {
        let isLoading = viewModel.loading[module] == true
        let isActive  = activeModule == module
        let hasOutput = !(viewModel.outputs[module] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasError  = viewModel.errors[module] != nil
        let isEnabled = isModuleEnabled(module) || isLoading

        // Glass tint carries the active state on macOS 26; the fallback mirrors
        // the pre-glass fills so macOS 15 keeps a visible active indicator
        // (glass replaces the old `matchedGeometryEffect` slide).
        let fallbackFill: AnyShapeStyle = isActive
            ? AnyShapeStyle(module.accentColor.opacity(compact ? 0.08 : 0.12))
            : (compact ? AnyShapeStyle(DS.Color.panel) : AnyShapeStyle(DS.Color.surfaceInset))

        Button { toggleModule(module) } label: {
            VStack(spacing: DS.Spacing.xxs) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: module.iconName)
                        .font(DS.Typography.icon(compact ? 12 : 14, weight: .medium))
                        .symbolEffect(.pulse, isActive: isLoading)
                        .frame(width: compact ? 14 : 18, height: compact ? 14 : 18)

                    if hasOutput && !isLoading {
                        statusDot(module.accentColor)
                    } else if hasError {
                        statusMark(DS.Color.danger)
                    }
                }

                Text(module.shortTitle)
                    .font(compact
                          ? .system(size: 8, weight: .regular)
                          : DS.Typography.caption2)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: compact ? 28 : 40)
            .foregroundStyle(
                !isEnabled ? DS.Color.textDisabled :
                isActive   ? module.accentColor :
                             compact ? DS.Color.textTertiary : DS.Color.textSecondary
            )
            .dsGlassInteractive(
                cornerRadius: DS.Radius.sm,
                // Neutral frosted glass for every chip — the active one reads via
                // its accent-colored glyph/label + accent stroke, not a colored
                // fill. Tinting the glass with the accent killed contrast against
                // the accent-colored label (`Glass.tint` is opaque and its alpha
                // can't be softened), so the color identity rides the content.
                tint: nil,
                fallback: fallbackFill,
                fallbackStroke: .none
            )
            .overlay {
                // Error / active edge that the glass tint alone doesn't convey.
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .stroke(
                        hasError && !isActive ? DS.Color.danger.opacity(0.26) :
                        isActive ? module.accentColor.opacity(0.36) : .clear,
                        lineWidth: 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
        }
        .buttonStyle(.plain)
        .animation(DS.Animation.springFast, value: isActive)
        .animation(DS.Animation.standard,   value: hasOutput)
        .if(shortcut != nil) { view in
            view.keyboardShortcut(shortcut!, modifiers: [.command])
        }
        .help(module.title)
        .disabled(!isEnabled)
        .accessibilityLabel(module.shortTitle)
        .accessibilityHint(isActive ? "Active module, tap to deselect" : "Tap to run \(module.shortTitle) analysis")
        .accessibilityValue(
            isLoading ? "Loading" :
            hasError  ? "Error" :
            hasOutput ? "Has output" : "No output"
        )
    }

    /// Small corner dot marking a module that has produced output.
    func statusDot(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 5, height: 5)
            .overlay(
                Circle().strokeBorder(DS.Color.surface, lineWidth: 1)
            )
            .offset(x: 3, y: -1)
    }

    /// Failure marker. Deliberately a different *shape* from `statusDot`, not
    /// just a different color: has-output and error were previously two dots
    /// telling apart only by hue, which is invisible to a colorblind reader
    /// (WCAG 1.4.1). The glyph carries the meaning on its own.
    private func statusMark(_ color: Color) -> some View {
        Image(systemName: "exclamationmark.circle.fill")
            .font(DS.Typography.icon(8, weight: .bold))
            .foregroundStyle(color)
            .background(
                Circle()
                    .fill(DS.Color.surface)
                    .frame(width: 9, height: 9)
            )
            .offset(x: 4, y: -2)
            .accessibilityHidden(true)   // the button's own value already says "Error"
    }
}
