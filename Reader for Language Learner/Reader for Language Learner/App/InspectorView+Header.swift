//
//  InspectorView+Header.swift
//  Reader for Language Learner
//
//  Compact selection header + inline action bar + control strip.
//

import SwiftUI

extension InspectorView {

    // MARK: - Saved State

    var isCurrentlySaved: Bool {
        savedWordsStore.isSaved(
            term: trimmedSelection,
            pdfFilename: pdfFilename,
            pageNumber: pageNumber
        )
    }

    // MARK: - Compact Selection Header

    var selectionHeader: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                Text(trimmedSelection)
                    .font(DS.Typography.headline)
                    .foregroundStyle(DS.Color.textPrimary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Selected text: \(trimmedSelection)")

                if isCurrentlySaved {
                    Label("Saved", systemImage: "checkmark.seal.fill")
                        .font(DS.Typography.caption2.weight(.semibold))
                        .foregroundStyle(DS.Color.success)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, 5)
                        .background(DS.Color.success.opacity(0.10))
                        .clipShape(Capsule())
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                        .accessibilityLabel("Word is saved to vocabulary")
                }
            }
            .animation(DS.Animation.springFast, value: isCurrentlySaved)

            Divider()

            actionBar
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
        .background(DS.Color.surfaceElevated.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .strokeBorder(DS.Color.separator.opacity(0.24), lineWidth: 0.6)
        )
    }

    // MARK: - Control Strip (Mode + Detail + Recent Terms)

    var controlStrip: some View {
        HStack(spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.xxs) {
                ForEach(ExplainMode.allCases) { mode in
                    Button { explainMode = mode } label: {
                        Text(mode.rawValue)
                            .font(DS.Typography.caption2.weight(explainMode == mode ? .bold : .regular))
                            .foregroundStyle(explainMode == mode ? DS.Color.accent : DS.Color.textTertiary)
                            .padding(.horizontal, DS.Spacing.sm)
                            .padding(.vertical, DS.Spacing.xxs + 1)
                            .background {
                                if explainMode == mode {
                                    Capsule()
                                        .fill(DS.Color.accentSubtle)
                                        .matchedGeometryEffect(id: "modeBackground", in: moduleNamespace)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.trailing, 2)

            Button {
                explainDetail = explainDetail == .short ? .detailed : .short
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: explainDetail == .short ? "text.alignleft" : "text.alignjustify")
                        .font(.system(size: 10, weight: .medium))
                    Text(explainDetail == .short ? "Short" : "Detailed")
                        .font(DS.Typography.caption2)
                }
                .foregroundStyle(DS.Color.textTertiary)
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.vertical, DS.Spacing.xxs + 1)
                .background(DS.Color.surfaceElevated.opacity(0.9))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(explainDetail == .short ? "Switch to Detailed" : "Switch to Short")

            recentTermsInline

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xs)
        .background(DS.Color.surface.opacity(0.76))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.sm)
                .strokeBorder(DS.Color.separator.opacity(0.14), lineWidth: 0.5)
        )
        .animation(DS.Animation.springFast, value: explainMode)
    }

    // MARK: - Recent Terms (inline)

    @ViewBuilder
    private var recentTermsInline: some View {
        let recents = viewModel.recentTerms.filter {
            $0.lowercased() != trimmedSelection.lowercased()
        }.prefix(4)

        if !recents.isEmpty {
            Divider()
                .frame(height: 12)
                .padding(.horizontal, DS.Spacing.xxs)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.xxs) {
                    ForEach(Array(recents), id: \.self) { term in
                        Button {
                            NotificationCenter.default.post(
                                name: .inspectorRecentTermSelected,
                                object: term
                            )
                        } label: {
                            Text(term)
                                .font(DS.Typography.caption2)
                                .foregroundStyle(DS.Color.textTertiary)
                                .padding(.horizontal, DS.Spacing.xs)
                                .padding(.vertical, DS.Spacing.xxs)
                                .background(DS.Color.surfaceInset.opacity(0.72))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Recent: \(term)")
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Recent terms")
        }
    }

    // MARK: - Action Bar (compact inline)

    var actionBar: some View {
        HStack(spacing: DS.Spacing.xs) {
            actionGroup {
                iconButton(
                    systemImage: speechManager.isSpeaking ? "speaker.wave.2.fill" : "play.fill",
                    help: speechManager.isSpeaking ? "Speaking…" : "Speak (⇧⌘S)",
                    action: speakSelection
                )
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!hasSelection)

                iconButton(
                    systemImage: "stop.fill",
                    help: "Stop (⇧⌘X)",
                    action: speechManager.stop
                )
                .keyboardShortcut("x", modifiers: [.command, .shift])
                .disabled(!speechManager.isSpeaking)
            }

            actionSpacer()

            actionGroup {
                iconButton(systemImage: "doc.on.doc", help: "Copy") {
                    copyToClipboard(trimmedSelection, showFeedback: true)
                }

                iconButton(
                    systemImage: isCurrentlySaved ? "star.fill" : "star",
                    help: isCurrentlySaved ? "Unsave (⌘D)" : "Save (⌘D)",
                    action: toggleSaveWord
                )
                .keyboardShortcut("d", modifiers: [.command])
                .foregroundStyle(isCurrentlySaved ? .yellow : .primary)

                iconButton(systemImage: "square.and.arrow.up", help: "Quick Export") {
                    Task { await quickExport() }
                }

                iconButton(systemImage: "ellipsis.circle", help: "Full Export… (⌘E)") {
                    showAnkiExport = true
                }
                .keyboardShortcut("e", modifiers: [.command])
            }

            Spacer(minLength: DS.Spacing.xs)

            actionSpacer()

            actionGroup {
                iconButton(systemImage: "trash", help: "Clear outputs", role: .destructive) {
                    viewModel.resetAll(); activeModule = nil
                }
                .disabled(isAnyLoading)
                .foregroundStyle(DS.Color.danger.opacity(0.78))

                iconButton(systemImage: "gearshape", help: "Settings (⌘,)") {
                    openSettings()
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }
        .controlSize(.mini)
    }

    @ViewBuilder
    private func actionGroup<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: DS.Spacing.xxs) {
            content()
        }
    }
}
