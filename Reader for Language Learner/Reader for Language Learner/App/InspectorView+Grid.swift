//
//  InspectorView+Grid.swift
//  Reader for Language Learner
//
//  Module grid — primary row + secondary overflow row.
//

import SwiftUI

extension InspectorView {

    // MARK: - Module Grid

    var moduleGrid: some View {
        VStack(spacing: DS.Spacing.sm) {
            // Primary row — keyboard shortcuts ⌘1…⌘5
            HStack(spacing: DS.Spacing.xs) {
                ForEach(Array(primaryModules.enumerated()), id: \.element) { index, module in
                    moduleButton(
                        for: module,
                        shortcut: KeyEquivalent(Character(String(index + 1)))
                    )
                }
            }
            .padding(DS.Spacing.xs)
            .background(DS.Color.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))

            // Run All button
            Button {
                runAllPrimaryModules()
            } label: {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Run All")
                        .font(DS.Typography.caption2.weight(.semibold))
                }
                .foregroundStyle(DS.Color.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.xs)
                .background(DS.Color.accentSubtle)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!hasSelection)
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .help("Run all primary modules (⇧⌘R)")

            // Overflow row — compact, ⌘6…⌘0
            let overflowKeys: [Character] = ["6", "7", "8", "9", "0"]
            HStack(spacing: DS.Spacing.xs) {
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
            VStack(spacing: DS.Spacing.xxs + 1) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: module.iconName)
                        .font(.system(size: compact ? 13 : 16, weight: .medium))
                        .symbolEffect(.pulse, isActive: isLoading)
                        .frame(width: compact ? 16 : 20, height: compact ? 16 : 20)

                    if hasOutput && !isLoading {
                        Circle()
                            .fill(module.accentColor)
                            .frame(width: 5, height: 5)
                            .offset(x: 3, y: -3)
                    } else if hasError {
                        Circle()
                            .fill(DS.Color.danger)
                            .frame(width: 5, height: 5)
                            .offset(x: 3, y: -3)
                    }
                }

                Text(module.shortTitle)
                    .font(compact
                          ? DS.Typography.caption2
                          : .system(size: 10, weight: .regular))
                    .lineLimit(1)

                if let shortcut, !compact {
                    Text("⌘\(shortcut.character)")
                        .font(.system(size: 8, weight: .regular, design: .monospaced))
                        .foregroundStyle(DS.Color.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: compact ? 36 : 52)
            .foregroundStyle(
                !isEnabled ? DS.Color.textDisabled :
                isActive   ? module.accentColor    :
                             DS.Color.textSecondary
            )
            .background {
                if isActive {
                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                        .fill(module.accentColor.opacity(0.10))
                        .matchedGeometryEffect(id: "activeModule", in: moduleNamespace)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .stroke(
                        hasError && !isActive ? DS.Color.danger.opacity(0.25) :
                        isActive ? module.accentColor.opacity(0.30) : .clear,
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
