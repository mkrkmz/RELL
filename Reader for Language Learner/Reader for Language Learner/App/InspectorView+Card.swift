//
//  InspectorView+Card.swift
//  Reader for Language Learner
//
//  The buttons inside the Inspector's card (Roadmap v18 Sprint 2, approved
//  mockup — the user's idea). The upper row: Save and the actions on the
//  card (Listen, Anki, Copy) and •••. The lower row, under a hairline: the
//  modules and passage tools on the card — the open module lit, a dot on
//  those with an answer ready. Which items sit on the card is the reader's
//  choice (`InspectorCardLayout`): Edit Card…, right-click, or "Add to Card"
//  in •••. What doesn't fit the column moves into ••• on its own; the row
//  never wraps, so the card's height never depends on its width. This
//  replaced the "Explanations" section and its module tiles.
//

import AppKit
import SwiftUI

extension InspectorView {

    var cardKind: CardKind { isSingleWordSelection ? .word : .sentence }

    /// The card's items, re-read when the reader changes them.
    var cardItems: [CardItem] {
        _ = cardRevision
        return InspectorCardLayout.load(cardKind)
    }

    // MARK: Upper row

    var cardActionsRow: some View {
        HStack(spacing: DS.Spacing.xxs) {
            if isSingleWordSelection {
                Button(action: toggleSaveWord) {
                    Label(isCurrentlySaved ? "Saved" : "Save", systemImage: isCurrentlySaved ? "star.fill" : "star")
                }
                .buttonStyle(.dsQuiet)
                .keyboardShortcut("d", modifiers: [.command])
                .help(isCurrentlySaved ? "Remove from saved vocabulary (⌘D)" : "Save to vocabulary (⌘D)")
            }

            ForEach(cardItems.filter(\.isAction), id: \.self) { item in
                cardButton(item)
            }

            Spacer(minLength: 0)

            cardMenu
        }
        .lineLimit(1)
        // Shortcuts that work whether or not their button is on the card.
        .background(exportShortcutButton)
        .background(stopShortcutButton)
        .background(listenShortcutButton)
        .background(runAllShortcutButton)
    }

    // MARK: Lower row

    /// The modules and tools on the card that fit the column, in order.
    private var fittingLowerItems: (shown: [CardItem], overflow: [CardItem]) {
        let items = cardItems.filter { !$0.isAction }
        let count = InspectorCardLayout.fittingCount(
            widths: items.map { Self.estimatedWidth(of: $0, kind: cardKind) },
            available: Double(cardRowWidth),
            spacing: Double(DS.Spacing.xxs)
        )
        return (Array(items.prefix(count)), Array(items.dropFirst(count)))
    }

    @ViewBuilder
    var cardModulesRow: some View {
        let shown = fittingLowerItems.shown
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Rectangle()
                .fill(DS.Color.accent.opacity(0.14))
                .frame(height: 1)
            HStack(spacing: DS.Spacing.xxs) {
                ForEach(shown, id: \.self) { item in
                    cardButton(item)
                }
                Spacer(minLength: 0)
            }
            .frame(height: 26)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { cardRowWidth = $0 }
        }
        .lineLimit(1)
    }

    // MARK: Buttons

    @ViewBuilder
    private func cardButton(_ item: CardItem) -> some View {
        switch item {
        case .module(let module):
            moduleCardButton(module)
        case .custom(let id):
            if let module = CustomModuleStore.shared.module(id) {
                customCardButton(module)
            }
        default:
            Button { perform(item) } label: {
                Label(cardTitle(item), systemImage: cardIcon(item))
            }
            .buttonStyle(.dsQuiet(isOn: item == .grammar && grammarLensExpanded))
            .disabled(!isAvailable(item))
            .help(cardHelp(item))
            .contextMenu { cardContextMenu(item) }
        }
    }

    private func moduleCardButton(_ module: ModuleType) -> some View {
        let isActive = displayedCustom == nil && displayedModule == module
        let isLoading = viewModel.loading[module] == true
        let hasOutput = !(viewModel.outputs[module] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasError = viewModel.errors[module] != nil
        return Button { toggleModule(module) } label: {
            Label(cardTitle(.module(module)), systemImage: module.iconName)
        }
        .buttonStyle(.dsQuiet(isOn: isActive, tint: module.accentColor))
        .overlay(alignment: .topTrailing) {
            if isLoading {
                ProgressView().controlSize(.mini).scaleEffect(0.6).offset(x: 2, y: -4)
            } else if hasError && !isActive {
                Circle().fill(DS.Color.danger).frame(width: 5, height: 5).offset(x: -2, y: 3)
            } else if hasOutput && !isActive {
                Circle().fill(module.accentColor).frame(width: 5, height: 5).offset(x: -2, y: 3)
            }
        }
        .disabled(!isModuleEnabled(module) && !isLoading)
        .help(module.title(nativeLanguage: nativeLanguage))
        .accessibilityValue(isActive ? Text("Open") : hasOutput ? Text("Answer ready") : Text(""))
        .contextMenu { cardContextMenu(.module(module)) }
    }

    private func customCardButton(_ module: CustomModule) -> some View {
        let isActive = activeCustom == module.id
        let isLoading = viewModel.customLoading[module.id] == true
        let hasOutput = !(viewModel.customOutputs[module.id] ?? "").isEmpty
        return Button { toggleCustom(module.id) } label: {
            Label(module.name, systemImage: module.icon)
        }
        .buttonStyle(.dsQuiet(isOn: isActive, tint: DS.Color.accent))
        .overlay(alignment: .topTrailing) {
            if isLoading {
                ProgressView().controlSize(.mini).scaleEffect(0.6).offset(x: 2, y: -4)
            } else if hasOutput && !isActive {
                Circle().fill(DS.Color.accent).frame(width: 5, height: 5).offset(x: -2, y: 3)
            }
        }
        .disabled(!hasSelection)
        .help(module.name)
        .contextMenu { cardContextMenu(.custom(module.id)) }
    }

    @ViewBuilder
    private func cardContextMenu(_ item: CardItem) -> some View {
        if case .custom(let id) = item {
            Button("Edit Module…") { openCustomModuleEditor(.edit(id)) }
            Divider()
        }
        Button("Remove from Card") { updateCard { InspectorCardLayout.unpin(item, in: $0) } }
        Button("Move Left") { updateCard { InspectorCardLayout.move(item, by: -1, in: $0) } }
        Button("Move Right") { updateCard { InspectorCardLayout.move(item, by: 1, in: $0) } }
        Divider()
        Button("Edit Card…") { showCardEditor = true }
    }

    // MARK: •••

    var cardMenu: some View {
        let unpinned = InspectorCardLayout.unpinned(cardKind, pinned: cardItems)
        let elsewhere = fittingLowerItems.overflow + unpinned
        return Menu {
            if !elsewhere.isEmpty {
                Section("More") {
                    ForEach(elsewhere, id: \.self) { item in
                        Button { perform(item) } label: {
                            Label(cardTitle(item), systemImage: cardIcon(item))
                        }
                        .disabled(!isAvailable(item))
                    }
                }
            }
            if !unpinned.isEmpty {
                Menu {
                    ForEach(unpinned, id: \.self) { item in
                        Button { updateCard { InspectorCardLayout.pin(item, in: $0) } } label: {
                            Label(cardTitle(item), systemImage: cardIcon(item))
                        }
                    }
                } label: {
                    Label("Add to Card", systemImage: "pin")
                }
            }
            Button {
                runAllPrimaryModules()
            } label: {
                Label("Run All (⇧⌘R)", systemImage: "square.stack.3d.down.forward")
            }
            .disabled(!hasSelection)

            Divider()

            if !isSingleWordSelection {
                Button(action: toggleSaveWord) {
                    Label(isCurrentlySaved ? "Remove from Saved" : "Save to Vocabulary",
                          systemImage: isCurrentlySaved ? "star.slash" : "star")
                }
                .disabled(!hasSelection)
            }
            if !cardItems.contains(.copy) {
                Button {
                    copyToClipboard(trimmedSelection, showFeedback: true)
                } label: {
                    Label("Copy Text", systemImage: "doc.on.doc")
                }
                .disabled(!hasSelection)
            }
            // Chosen from the selection now (one word: word, more: sentence);
            // still yours to override for this selection.
            Picker(selection: $explainMode) {
                ForEach(ExplainMode.allCases) { mode in
                    Text(mode.localizedTitle).tag(mode)
                }
            } label: {
                Label("Explain As", systemImage: "text.magnifyingglass")
            }
            Section("Anki") {
                Button {
                    Task { await quickExport() }
                } label: {
                    Label("Quick Export to Anki", systemImage: "square.and.arrow.up")
                }
                .disabled(!hasSelection)
                Button {
                    showAnkiExport = true
                } label: {
                    Label("Export Fields… (⌘E)", systemImage: "slider.horizontal.3")
                }
                .disabled(!hasSelection)
            }

            Divider()

            Button(role: .destructive) {
                viewModel.resetAll()
            } label: {
                Label("Clear Outputs", systemImage: "trash")
            }
            .disabled(isAnyLoading)
            Button("Edit Card…") { showCardEditor = true }
            Button("New Module…") { openCustomModuleEditor(.new) }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(DS.Typography.icon(13, weight: .medium))
                .foregroundStyle(DS.Color.accent)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More explanations and actions")
        .accessibilityLabel("More explanations and actions")
    }

    // MARK: Doing it

    private func perform(_ item: CardItem) {
        switch item {
        case .listen:
            if speechManager.isSpeaking { speechManager.stop() } else { speakSelection() }
        case .anki:
            Task { await quickExport() }
        case .copy:
            copyToClipboard(trimmedSelection, showFeedback: true)
        case .grammar:
            grammarLensExpanded.toggle()
        case .simplify:
            NotificationCenter.default.post(name: .simplifySelectionCommand, object: trimmedSelection)
        case .retell:
            NotificationCenter.default.post(name: .retellSelectionCommand, object: trimmedSelection)
        case .module(let module):
            toggleModule(module)
        case .custom(let id):
            toggleCustom(id)
        }
    }

    private func isAvailable(_ item: CardItem) -> Bool {
        guard hasSelection else { return false }
        switch item {
        case .grammar:           return GrammarLens.isEligible(trimmedSelection)
        case .simplify, .retell: return GradedRewrite.isEligible(trimmedSelection)
        case .module(let module): return isModuleEnabled(module)
        case .custom(let id):    return CustomModuleStore.shared.module(id) != nil
        default:                 return true
        }
    }

    private func updateCard(_ change: ([CardItem]) -> [CardItem]) {
        InspectorCardLayout.save(change(cardItems), for: cardKind)
    }

    // MARK: Names

    func cardTitle(_ item: CardItem) -> String {
        switch item {
        case .listen:   return speechManager.isSpeaking ? String(localized: "Stop") : String(localized: "Listen")
        case .module(let module):
            return CardItem.title(of: item, kind: cardKind, native: nativeLanguage) ?? module.shortTitle
        default:
            return CardItem.title(of: item, kind: cardKind, native: nativeLanguage) ?? ""
        }
    }

    func cardIcon(_ item: CardItem) -> String {
        if item == .listen, speechManager.isSpeaking { return "stop.fill" }
        return CardItem.icon(of: item)
    }

    private func cardHelp(_ item: CardItem) -> String {
        switch item {
        case .listen: return String(localized: "Speak selected text (⇧⌘S)")
        case .anki:   return String(localized: "Quick Export to Anki")
        case .copy:   return String(localized: "Copy Text")
        case .grammar: return String(localized: "Parts of speech and how the sentence is built")
        case .simplify, .retell:
            return GradedRewrite.isEligible(trimmedSelection)
                ? String(localized: "Simplify to your level, or retell it in your own words")
                : SelectionMenu.passageOnlyReason
        case .module(let module): return module.title(nativeLanguage: nativeLanguage)
        case .custom(let id): return CustomModuleStore.shared.module(id)?.name ?? ""
        }
    }

    /// The width a lower-row button takes: icon, gap, title, padding.
    static func estimatedWidth(of item: CardItem, kind: CardKind) -> Double {
        let title = CardItem.title(of: item, kind: kind, native: Language.storedNative) ?? ""
        let font = NSFont.systemFont(ofSize: NSFont.preferredFont(forTextStyle: .caption1).pointSize, weight: .semibold)
        let text = (title as NSString).size(withAttributes: [.font: font]).width
        return ceil(text) + 14 + Double(DS.Spacing.xs) + Double(DS.Spacing.sm + DS.Spacing.xxs) * 2 + 2
    }

    // MARK: Shortcuts kept when their button isn't on the card

    private var listenShortcutButton: some View {
        Button { speakSelection() } label: { Color.clear }
            .frame(width: 0, height: 0)
            .opacity(0)
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(!hasSelection)
            .accessibilityHidden(true)
    }

    var runAllShortcutButton: some View {
        Button { runAllPrimaryModules() } label: { Color.clear }
            .frame(width: 0, height: 0)
            .opacity(0)
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!hasSelection)
            .accessibilityHidden(true)
    }
}

// MARK: - Names and icons (shared with the card editor)

extension CardItem {
    /// nil for a module title that depends on the reader's native language
    /// only through `shortTitle`.
    static func title(of item: CardItem, kind: CardKind, native: Language) -> String? {
        switch item {
        case .listen:   return String(localized: "Listen")
        case .anki:     return String(localized: "Anki")
        case .copy:     return String(localized: "Copy")
        case .grammar:  return String(localized: "Grammar")
        case .simplify: return String(localized: "Simplify")
        case .retell:   return String(localized: "Retell")
        case .module(let module):
            if kind == .sentence, module == .definitionEN { return String(localized: "Explain") }
            if module == .meaningTR { return native.nativeName }
            return module.shortTitle
        case .custom(let id):
            return CustomModuleStore.shared.module(id)?.name ?? String(localized: "Own module")
        }
    }

    static func icon(of item: CardItem) -> String {
        switch item {
        case .listen:   return "play.fill"
        case .anki:     return "square.and.arrow.up"
        case .copy:     return "doc.on.doc"
        case .grammar:  return "textformat.abc"
        case .simplify: return "text.badge.checkmark"
        case .retell:   return "square.and.pencil"
        case .module(let module): return module.iconName
        case .custom(let id): return CustomModuleStore.shared.module(id)?.icon ?? "sparkles"
        }
    }
}
