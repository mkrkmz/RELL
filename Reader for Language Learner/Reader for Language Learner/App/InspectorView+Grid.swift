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
            .padding(.horizontal, DS.Spacing.xxs)
            .padding(.vertical, DS.Spacing.xs)
            .background(DS.Color.surfaceElevated.opacity(0.96))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .strokeBorder(DS.Color.separator.opacity(0.18), lineWidth: 0.6)
            )

            let overflowKeys: [Character] = ["6", "7", "8", "9", "0"]
            HStack(spacing: DS.Spacing.xxs) {
                ForEach(Array(overflowModules.enumerated()), id: \.element) { index, module in
                    moduleButton(
                        for: module,
                        shortcut: index < overflowKeys.count
                            ? KeyEquivalent(overflowKeys[index])
                            : nil,
                        compact: true
                    )
                }
            }
            .padding(.horizontal, DS.Spacing.xs)
            .padding(.vertical, DS.Spacing.xs)
            .background(DS.Color.surfaceInset.opacity(0.70))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .strokeBorder(DS.Color.separator.opacity(0.12), lineWidth: 0.5)
            )
        }
        .animation(DS.Animation.snappy, value: explainMode)
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
