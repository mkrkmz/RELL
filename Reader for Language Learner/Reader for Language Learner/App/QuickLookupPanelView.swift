//
//  QuickLookupPanelView.swift
//  Reader for Language Learner
//
//  Spotlight-style quick lookup surface, shared by the ⌃⌥Space HUD panel and
//  the menu bar extra window: type a word anywhere, get the definition,
//  save it to the vocabulary in one keystroke.
//

import SwiftUI

// MARK: - Model

@MainActor
@Observable
final class QuickLookupPanelModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded(String)
        case failed(String)
    }

    var query: String = ""
    private(set) var phase: Phase = .idle
    /// The term the current phase belongs to (query may have changed since).
    private(set) var lookedUpTerm: String = ""

    private var lookupTask: Task<Void, Never>?

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func lookup() {
        let term = trimmedQuery
        guard !term.isEmpty else { return }

        lookupTask?.cancel()
        lookedUpTerm = term

        // Cache-first: saved words and the LRU answer instantly.
        if let cached = QuickLookupService.shared.cachedDefinition(
            for: term,
            savedWordsStore: SavedWordsStore.shared
        ) {
            phase = .loaded(cached)
            return
        }

        phase = .loading
        lookupTask = Task { [weak self] in
            do {
                let definition = try await QuickLookupService.shared.definition(for: term)
                guard !Task.isCancelled, let self, self.lookedUpTerm == term else { return }
                if definition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.phase = .failed("The model returned an empty answer. Try again or check the model in Settings.")
                } else {
                    self.phase = .loaded(definition)
                }
            } catch {
                guard !Task.isCancelled, let self, self.lookedUpTerm == term else { return }
                self.phase = .failed(LLMErrorMessage.userMessage(for: error))
            }
        }
    }

    func saveWord() {
        guard case .loaded(let definition) = phase, !lookedUpTerm.isEmpty else { return }
        SavedWordsStore.shared.add(SavedWord(
            term: lookedUpTerm,
            sentence: "",
            pdfFilename: nil,
            pageNumber: nil,
            mode: ExplainMode.word.rawValue.lowercased(),
            domain: DomainPreference.general.rawValue.lowercased(),
            llmOutputs: [ModuleType.definitionEN.rawValue: definition]
        ))
    }

    var isCurrentTermSaved: Bool {
        guard !lookedUpTerm.isEmpty else { return false }
        let key = lookedUpTerm.lowercased()
        return SavedWordsStore.shared.words.contains { $0.term.lowercased() == key }
    }

    func reset() {
        lookupTask?.cancel()
        query = ""
        lookedUpTerm = ""
        phase = .idle
    }
}

// MARK: - View

/// The two hosting surfaces need different chrome: the floating HUD paints
/// its own material and rounded border, while the menu bar window already
/// provides both — double materials made the text unreadable.
enum QuickLookupPanelStyle {
    case hud
    case menuBar
}

struct QuickLookupPanelView: View {
    var style: QuickLookupPanelStyle = .hud
    /// Closes the hosting surface (HUD panel or menu bar window).
    var onDismiss: (() -> Void)? = nil
    /// Reports content-size changes so the HUD panel can grow with results.
    var onSizeChange: ((CGSize) -> Void)? = nil

    @State private var model = QuickLookupPanelModel()
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField

            switch model.phase {
            case .idle:
                idleHint
            case .loading:
                loadingRow
            case .loaded(let definition):
                resultView(definition)
            case .failed(let message):
                failureView(message)
            }
        }
        .frame(width: 420)
        .modifier(PanelChrome(style: style))
        .onGeometryChange(for: CGSize.self, of: \.size) { size in
            onSizeChange?(size)
        }
        .onExitCommand { dismiss() }
        .onAppear {
            searchFocused = true
        }
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "character.book.closed")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(DS.Color.accent)

            TextField("Look up a word…", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .focused($searchFocused)
                .onSubmit { model.lookup() }

            if !model.query.isEmpty {
                Button {
                    model.reset()
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DS.Color.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.md)
    }

    // MARK: Phases

    private var idleHint: some View {
        Text("Press Return to look up · Esc to close")
            .font(DS.Typography.caption)
            .foregroundStyle(DS.Color.textTertiary)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.md)
    }

    private var loadingRow: some View {
        HStack(spacing: DS.Spacing.sm) {
            ProgressView()
                .controlSize(.small)
            Text("Asking \(shortModelName)…")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.textSecondary)
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.bottom, DS.Spacing.md)
    }

    private func resultView(_ definition: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Divider()

            // No ScrollView: self-sizing windows (menu bar extra, the HUD
            // panel) collapse a ScrollView to its ~zero ideal height. Plain
            // Text sizes the window to the content; definitions are short.
            Text(definition)
                .font(DS.Typography.body)
                .foregroundStyle(DS.Color.textPrimary)
                .textSelection(.enabled)
                .lineLimit(14)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                SpeakButton(text: model.lookedUpTerm)

                Spacer()

                if model.isCurrentTermSaved {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.success)
                } else {
                    Button("Save Word") { model.saveWord() }
                        .controlSize(.small)
                        .keyboardShortcut("s", modifiers: [.command])
                        .help("Save to vocabulary (⌘S)")
                }
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.bottom, DS.Spacing.md)
    }

    private func failureView(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Retry") { model.lookup() }
                .controlSize(.small)
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.bottom, DS.Spacing.md)
    }

    // MARK: Helpers

    private func dismiss() {
        onDismiss?()
    }

    private var shortModelName: String {
        let model = LLMConfiguration().model
        return model.components(separatedBy: "/").last ?? model
    }
}

// MARK: - Chrome

private struct PanelChrome: ViewModifier {
    let style: QuickLookupPanelStyle

    func body(content: Content) -> some View {
        switch style {
        case .hud:
            // .popover material adapts to light/dark, so .primary text
            // always contrasts (unlike the fixed-dark .hudWindow).
            content
                .background(
                    VisualEffectView(material: .popover, blendingMode: .behindWindow)
                )
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.lg)
                        .strokeBorder(DS.Color.separator.opacity(0.35), lineWidth: 0.8)
                )
        case .menuBar:
            // The MenuBarExtra window supplies its own material and corners.
            content
        }
    }
}
