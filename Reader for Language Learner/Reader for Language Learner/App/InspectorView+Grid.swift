//
//  InspectorView+Grid.swift
//  Reader for Language Learner
//
//  Module grid — primary row + overflow row, compact layout.
//

import SwiftUI

extension InspectorView {

    // MARK: - Module Grid

    var moduleGrid: some View {
        VStack(spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.xxs) {
                ForEach(Array(primaryModules.enumerated()), id: \.element) { index, module in
                    moduleButton(
                        for: module,
                        shortcut: KeyEquivalent(Character(String(index + 1)))
                    )
                }
                runAllButton
            }
            .padding(.horizontal, DS.Spacing.xxs)
            .padding(.vertical, DS.Spacing.xs)
            .background(DS.Color.surfaceElevated.opacity(0.96))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .strokeBorder(DS.Color.separator.opacity(0.18), lineWidth: 0.6)
            )

            moreModulesToggle

            if showMoreModules {
                HStack(spacing: DS.Spacing.xxs) {
                    ForEach(overflowModules, id: \.self) { module in
                        // Shortcuts (⌘6-0) live on the hidden buttons below so
                        // they keep working while this row is collapsed.
                        moduleButton(for: module, shortcut: nil)
                    }
                    // Mirror the Run All slot so columns align with the primary row.
                    Color.clear.frame(width: 34, height: 1)
                }
                .padding(.horizontal, DS.Spacing.xxs)
                .padding(.vertical, DS.Spacing.xs)
                .background(DS.Color.surfaceElevated.opacity(0.96))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                        .strokeBorder(DS.Color.separator.opacity(0.18), lineWidth: 0.6)
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(overflowShortcutButtons)
        .animation(DS.Animation.snappy, value: explainMode)
        .animation(DS.Animation.snappy, value: showMoreModules)
    }

    // MARK: - Run All

    private var runAllButton: some View {
        Button {
            runAllPrimaryModules()
        } label: {
            Image(systemName: "play.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(hasSelection ? DS.Color.accent : DS.Color.textDisabled)
                .frame(width: 34, height: 34)
                .background(DS.Color.surfaceInset.opacity(0.94))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                        .strokeBorder(DS.Color.separator.opacity(0.20), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .disabled(!hasSelection)
        .keyboardShortcut("r", modifiers: [.command, .shift])
        .help("Run All (⇧⌘R)")
        .accessibilityLabel("Run All Modules")
    }

    // MARK: - More Modules Disclosure

    private var moreModulesToggle: some View {
        Button {
            withAnimation(DS.Animation.snappy) { showMoreModules.toggle() }
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: showMoreModules ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                Text(showMoreModules ? "Fewer modules" : "More modules")
                if !showMoreModules && overflowHasOutput {
                    Circle()
                        .fill(DS.Color.accent.opacity(0.8))
                        .frame(width: 5, height: 5)
                }
            }
            .font(DS.Typography.caption2)
            .foregroundStyle(DS.Color.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(showMoreModules ? "Hide extra modules" : "Show \(overflowModules.count) more modules")
    }

    private var overflowHasOutput: Bool {
        overflowModules.contains { module in
            !(viewModel.outputs[module] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Always-present invisible buttons that keep ⌘6-0 bound to the overflow
    /// modules even when the disclosure row is collapsed.
    private var overflowShortcutButtons: some View {
        let keys: [Character] = ["6", "7", "8", "9", "0"]
        return ZStack {
            ForEach(Array(overflowModules.enumerated()), id: \.element) { index, module in
                if index < keys.count {
                    Button { toggleModule(module) } label: { Color.clear }
                        .frame(width: 0, height: 0)
                        .opacity(0)
                        .keyboardShortcut(KeyEquivalent(keys[index]), modifiers: [.command])
                        .disabled(!isModuleEnabled(module))
                        .accessibilityHidden(true)
                }
            }
        }
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

        Button { toggleModule(module) } label: {
            VStack(spacing: DS.Spacing.xxs) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: module.iconName)
                        .font(.system(size: compact ? 12 : 14, weight: .medium))
                        .symbolEffect(.pulse, isActive: isLoading)
                        .frame(width: compact ? 14 : 18, height: compact ? 14 : 18)

                    if hasOutput && !isLoading {
                        Capsule()
                            .fill(module.accentColor.opacity(0.90))
                            .frame(width: 8, height: 4)
                            .offset(x: 2, y: -2)
                    } else if hasError {
                        Capsule()
                            .fill(DS.Color.danger.opacity(0.88))
                            .frame(width: 8, height: 4)
                            .offset(x: 2, y: -2)
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
            .background {
                if isActive {
                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                        .fill(module.accentColor.opacity(compact ? 0.08 : 0.12))
                        .matchedGeometryEffect(id: "activeModule", in: moduleNamespace)
                } else if compact {
                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                        .fill(DS.Color.surface.opacity(0.72))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .stroke(
                        hasError && !isActive ? DS.Color.danger.opacity(0.26) :
                        isActive ? module.accentColor.opacity(0.36) :
                        compact ? DS.Color.separator.opacity(0.06) : .clear,
                        lineWidth: compact ? 0.8 : 1
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
        .disabled(!isEnabled)
        .accessibilityLabel(module.shortTitle)
        .accessibilityHint(isActive ? "Active module, tap to deselect" : "Tap to run \(module.shortTitle) analysis")
        .accessibilityValue(
            isLoading ? "Loading" :
            hasError  ? "Error" :
            hasOutput ? "Has output" : "No output"
        )
    }
}
