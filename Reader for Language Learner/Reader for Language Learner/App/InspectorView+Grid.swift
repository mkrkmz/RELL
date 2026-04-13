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
            // Primary row — keyboard shortcuts ⌘1…⌘5 + Run All button
            HStack(spacing: DS.Spacing.xxs) {
                ForEach(Array(primaryModules.enumerated()), id: \.element) { index, module in
                    moduleButton(
                        for: module,
                        shortcut: KeyEquivalent(Character(String(index + 1)))
                    )
                }

                // Run All — compact circular button at trailing edge
                Button {
                    runAllPrimaryModules()
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.Color.accent)
                        .frame(width: 30, height: 30)
                        .background(DS.Color.accentSubtle)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!hasSelection)
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .help("Run All (⇧⌘R)")
                .accessibilityLabel("Run All Modules")
            }
            .padding(DS.Spacing.xxs)
            .background(DS.Color.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))

            // Overflow row — compact, ⌘6…⌘0
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
            .padding(.horizontal, DS.Spacing.xxs)
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
                        Circle()
                            .fill(module.accentColor)
                            .frame(width: 4, height: 4)
                            .offset(x: 2, y: -2)
                    } else if hasError {
                        Circle()
                            .fill(DS.Color.danger)
                            .frame(width: 4, height: 4)
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
