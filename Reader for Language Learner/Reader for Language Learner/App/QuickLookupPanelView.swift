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
        case streaming(String)
        case loaded(String)
        case failed(String)
    }

    var query: String = ""
    private(set) var phase: Phase = .idle
    /// The term the current phase belongs to (query may have changed since).
    private(set) var lookedUpTerm: String = ""
    /// Native-language meaning, fetched after the definition settles. Shown
    /// as a subtitle below the definition once it arrives.
    private(set) var nativeMeaning: String?

    private var lookupTask: Task<Void, Never>?
    private var nativeMeaningTask: Task<Void, Never>?

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func lookup(service: QuickLookupService, savedWords: SavedWordsStore) {
        let term = trimmedQuery
        guard !term.isEmpty else { return }

        lookupTask?.cancel()
        nativeMeaningTask?.cancel()
        lookedUpTerm = term
        nativeMeaning = nil

        // Cache-first: saved words and the LRU answer instantly.
        if let cached = service.cachedDefinition(for: term, savedWordsStore: savedWords) {
            phase = .loaded(cached)
            fetchNativeMeaning(for: term, service: service)
            return
        }

        phase = .loading
        lookupTask = Task { [weak self] in
            do {
                let definition = try await service.streamDefinition(for: term) { partial in
                    guard let self, self.lookedUpTerm == term else { return }
                    self.phase = .streaming(partial)
                }
                guard !Task.isCancelled, let self, self.lookedUpTerm == term else { return }
                if definition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.phase = .failed(String(localized: "The model returned an empty answer. Try again or check the model in Settings."))
                } else {
                    self.phase = .loaded(definition)
                    self.fetchNativeMeaning(for: term, service: service)
                }
            } catch {
                guard !Task.isCancelled, let self, self.lookedUpTerm == term else { return }
                self.phase = .failed(LLMErrorMessage.userMessage(for: error))
            }
        }
    }

    private func fetchNativeMeaning(for term: String, service: QuickLookupService) {
        if let cached = service.cachedNativeMeaning(for: term) {
            nativeMeaning = cached
            return
        }
        nativeMeaningTask = Task { [weak self] in
            guard let meaning = try? await service.nativeMeaning(for: term) else { return }
            guard !Task.isCancelled, let self, self.lookedUpTerm == term else { return }
            self.nativeMeaning = meaning
        }
    }

    func saveWord(to store: SavedWordsStore) {
        guard case .loaded(let definition) = phase, !lookedUpTerm.isEmpty else { return }
        var outputs = [ModuleType.definitionEN.rawValue: definition]
        if let nativeMeaning {
            outputs[ModuleType.meaningTR.rawValue] = nativeMeaning
        }
        store.add(SavedWord(
            term: lookedUpTerm,
            sentence: "",
            pdfFilename: nil,
            pageNumber: nil,
            mode: ExplainMode.word.rawValue.lowercased(),
            domain: DomainPreference.general.rawValue.lowercased(),
            llmOutputs: outputs,
            language: Language.storedTarget.rawValue
        ))
    }

    func isCurrentTermSaved(in store: SavedWordsStore) -> Bool {
        guard !lookedUpTerm.isEmpty else { return false }
        let key = lookedUpTerm.lowercased()
        return store.words.contains { $0.term.lowercased() == key }
    }

    func reset() {
        lookupTask?.cancel()
        nativeMeaningTask?.cancel()
        query = ""
        lookedUpTerm = ""
        nativeMeaning = nil
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
    let style: QuickLookupPanelStyle
    /// Closes the hosting surface (HUD panel or menu bar window).
    let onDismiss: (() -> Void)?
    /// Reports content-size changes so the HUD panel can grow with results.
    let onSizeChange: ((CGSize) -> Void)?

    @State private var model: QuickLookupPanelModel
    @FocusState private var searchFocused: Bool

    @Environment(QuickLookupService.self) private var quickLookup
    @Environment(SavedWordsStore.self) private var savedWordsStore

    /// `model` may be supplied by the HUD controller so external entry
    /// points (Services menu) can prefill and trigger a lookup.
    init(
        style: QuickLookupPanelStyle = .hud,
        model: QuickLookupPanelModel? = nil,
        onDismiss: (() -> Void)? = nil,
        onSizeChange: ((CGSize) -> Void)? = nil
    ) {
        self.style = style
        self.onDismiss = onDismiss
        self.onSizeChange = onSizeChange
        self._model = State(initialValue: model ?? QuickLookupPanelModel())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField

            switch model.phase {
            case .idle:
                idleHint
            case .loading:
                loadingRow
            case .streaming(let partial):
                resultView(partial, isFinal: false)
            case .loaded(let definition):
                resultView(definition, isFinal: true)
            case .failed(let message):
                failureView(message)
            }
        }
        .frame(width: DS.Layout.hudWidth)
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
                .font(DS.Typography.icon(15, weight: .medium))
                .foregroundStyle(DS.Color.accent)

            TextField("Look up a word…", text: $model.query)
                .textFieldStyle(.plain)
                .font(.title2)
                .focused($searchFocused)
                .onSubmit { model.lookup(service: quickLookup, savedWords: savedWordsStore) }

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

    private func resultView(_ definition: String, isFinal: Bool) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Divider()

            // No ScrollView: self-sizing windows (menu bar extra, the HUD
            // panel) collapse a ScrollView to its ~zero ideal height. Plain
            // Text sizes the window to the content; definitions are short.
            // `definition` already arrives cleaned once final (both the
            // cache-hit and streamDefinition paths sanitize before handing
            // it back); the streaming partial is intentionally left raw.
            Text(definition)
                .font(DS.Typography.body)
                .foregroundStyle(DS.Color.textPrimary)
                .textSelection(.enabled)
                .lineLimit(14)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isFinal, let nativeMeaning = model.nativeMeaning {
                Text(nativeMeaning)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textSecondary)
                    .textSelection(.enabled)
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if isFinal {
                HStack {
                    SpeakButton(text: model.lookedUpTerm)

                    Spacer()

                    if model.isCurrentTermSaved(in: savedWordsStore) {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Color.success)
                    } else {
                        Button("Save Word") { model.saveWord(to: savedWordsStore) }
                            .controlSize(.small)
                            .keyboardShortcut("s", modifiers: [.command])
                            .help("Save to vocabulary (⌘S)")
                    }
                }
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.bottom, DS.Spacing.md)
    }

    private func failureView(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DS.Color.warning)
            Text(message)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Retry") { model.lookup(service: quickLookup, savedWords: savedWordsStore) }
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
                        .strokeBorder(DS.Color.hairline, lineWidth: 0.8)
                )
        case .menuBar:
            // The MenuBarExtra window supplies its own material and corners.
            content
        }
    }
}
