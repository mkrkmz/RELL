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
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            DSSectionHeader("Modules") {
                runAllButton
            }
            .padding(.horizontal, DS.Spacing.xxs)

            VStack(spacing: DS.Spacing.xs) {
                HStack(spacing: DS.Spacing.xxs) {
                    ForEach(Array(primaryModules.enumerated()), id: \.element) { index, module in
                        moduleButton(
                            for: module,
                            shortcut: KeyEquivalent(Character(String(index + 1)))
                        )
                    }
                }
                .padding(.horizontal, DS.Spacing.xxs)

                if showMoreModules {
                    HStack(spacing: DS.Spacing.xxs) {
                        ForEach(overflowModules, id: \.self) { module in
                            // Shortcuts (⌘6-0) live on the hidden buttons below so
                            // they keep working while this row is collapsed.
                            moduleButton(for: module, shortcut: nil)
                        }
                    }
                    .padding(.horizontal, DS.Spacing.xxs)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                moreModulesToggle
            }
        }
        .background(overflowShortcutButtons)
        .animation(DS.Animation.snappy, value: explainMode)
        .animation(DS.Animation.snappy, value: showMoreModules)
    }

    // MARK: - Run All (section-header action)

    private var runAllButton: some View {
        Button {
            runAllPrimaryModules()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "play.fill")
                    .font(.system(size: 8, weight: .bold))
                Text("Run All")
                    .font(DS.Typography.caption2.weight(.semibold))
            }
            .foregroundStyle(hasSelection ? DS.Color.accent : DS.Color.textDisabled)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.xxs + 1)
            .background(hasSelection ? DS.Color.accentSubtle : DS.Color.cardSoft)
            .clipShape(Capsule())
            .overlay(
                Capsule().strokeBorder(
                    hasSelection ? DS.Color.accentMuted.opacity(0.45) : DS.Color.hairline,
                    lineWidth: 0.6
                )
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
                Spacer(minLength: 0)
            }
            .font(DS.Typography.caption2)
            .foregroundStyle(DS.Color.textTertiary)
            .padding(.vertical, 3)
            .padding(.horizontal, DS.Spacing.xxs)
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
                        statusDot(module.accentColor)
                    } else if hasError {
                        statusDot(DS.Color.danger)
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
                        .fill(DS.Color.panel)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .stroke(
                        hasError && !isActive ? DS.Color.danger.opacity(0.26) :
                        isActive ? module.accentColor.opacity(0.36) :
                        compact ? DS.Color.hairline : .clear,
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

    /// Small corner status dot for a module button (has-output / error).
    private func statusDot(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 5, height: 5)
            .overlay(
                Circle().strokeBorder(DS.Color.surface, lineWidth: 1)
            )
            .offset(x: 3, y: -1)
    }
}
