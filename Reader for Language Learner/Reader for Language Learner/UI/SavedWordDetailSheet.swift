//
//  SavedWordDetailSheet.swift
//  Reader for Language Learner
//
//  The word page (Roadmap v13 Sprint 1; split out of `SavedWordsListView` in
//  v10 Sprint 4). Leads with the word and how well it's remembered, then
//  everywhere it has turned up in your reading since — each sentence opens
//  the book at that page. Editing (tags, notes, saved outputs) sits below
//  under Details.
//

import SwiftUI

struct SavedWordDetailSheet: View {
    @State var word: SavedWord
    var store: SavedWordsStore
    /// In the word notebook's third column (v16 S2): no Save/Cancel —
    /// edits are saved as they're made; deleting asks first.
    var isPane: Bool = false
    /// Bumped by the notebook's Return: focus moves to the card's first
    /// field (v18 S5).
    var focusRequest: Int = 0
    @Environment(WordEncounterStore.self) var encounterStore
    @Environment(\.dismiss) var dismiss
    @Environment(\.openWindow) var openWindow
    @Environment(WordEnricher.self) private var enricher: WordEnricher?
    @Environment(QuickLookupService.self) var quickLookup: QuickLookupService?
    @State var isTranslating = false
    @AppStorage(StorageKey.fillUsesProvider) private var fillUsesProvider = true

    @State var showAllEncounters = false
    @State private var confirmDelete = false
    @State private var isFilling = false
    /// The last fill found nothing for the empty fields.
    @State private var nothingMoreFound = false
    @State private var editingField: FillField?
    @State private var editText = ""
    @State private var showDetails = false
    @State private var showWriting = false
    @State var repeating = false
    @FocusState private var focusedField: FillField?

    /// Encounters shown before "Show all".
    static let collapsedEncounterCount = 6

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var language: Language {
        word.language.flatMap(Language.init(rawValue:)) ?? Language.storedTarget
    }

    /// The meaning in your language, else the definition — the hero's line.
    private var definition: String? {
        SavedWordRow.oneLineMeaning(of: word).map { MarkdownUtils.sanitizeLLMOutput($0) }
    }

    /// Fields the card section lists, in card order.
    private static let cardFields: [FillField] = [.meaning, .definition, .pronunciation, .examples, .level, .mnemonic]

    /// The card's rows: the memory hook only once there is one, or for a
    /// word you keep forgetting (v15 S3).
    private var shownCardFields: [FillField] {
        Self.cardFields.filter { $0 != .mnemonic || word.isStruggling || !$0.isMissing(in: word) }
    }

    var body: some View {
        if isPane {
            paneBody
        } else {
            sheetBody
        }
    }

    // MARK: - Pane (v16 S2)

    /// The fields this page edits. Saved as they change — into the stored
    /// word, so a review made meanwhile in the study room isn't undone.
    private struct Edits: Equatable {
        var tags: [String]
        var notes: String
        var llmOutputs: [String: String]
        var fieldSources: [String: String]
        var cefrLevel: String?
        var cefrIsAuto: Bool
    }

    private var edits: Edits {
        Edits(tags: word.tags, notes: word.notes, llmOutputs: word.llmOutputs,
              fieldSources: word.fieldSources, cefrLevel: word.cefrLevel, cefrIsAuto: word.cefrIsAuto)
    }

    /// Writes only what changed between `old` and `new` — a field changed
    /// elsewhere meanwhile (a level set from the list) keeps its new value.
    private func saveEdits(from old: Edits, to new: Edits) {
        guard var latest = store.word(withID: word.id) else { return }
        let before = latest
        if old.tags != new.tags { latest.tags = new.tags }
        if old.notes != new.notes { latest.notes = new.notes }
        if old.llmOutputs != new.llmOutputs { latest.llmOutputs = new.llmOutputs }
        if old.fieldSources != new.fieldSources { latest.fieldSources = new.fieldSources }
        if old.cefrLevel != new.cefrLevel || old.cefrIsAuto != new.cefrIsAuto {
            latest.cefrLevel = new.cefrLevel
            latest.cefrIsAuto = new.cefrIsAuto
        }
        if latest != before { store.update(latest) }
    }

    /// The memory read-out follows the stored word in the pane: reviews
    /// happen elsewhere while it's open.
    var current: SavedWord {
        isPane ? (store.word(withID: word.id) ?? word) : word
    }

    private var paneBody: some View {
        VStack(spacing: 0) {
            ScrollView {
                pageSections
                    .padding(DS.Spacing.lg)
            }
            Divider()
            HStack {
                Button("Delete…", role: .destructive) { confirmDelete = true }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .help("Delete (⌘⌫)")
                Spacer()
                Text("Changes are saved as you make them.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.sm)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: edits) { old, new in saveEdits(from: old, to: new) }
        .onChange(of: focusRequest) { _, _ in focusedField = shownCardFields.first }
        .confirmationDialog("Delete “\(word.term)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { store.delete(word) }
        } message: {
            Text("Its reviews and sentences go with it.")
        }
    }

    @ViewBuilder
    private var pageSections: some View {
        if word.isSentence {
            sentenceSections
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                hero
                cardSection
                memoryCard
                encountersSection
                yourSentences
                if !word.sentence.isEmpty { savedContext }
                detailsSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .sheet(isPresented: $showWriting) {
                SentenceWritingCard(word: current, onDone: { showWriting = false })
                    .padding(DS.Spacing.lg)
                    .frame(width: 560)
                    .environment(store)
            }
        }
    }


    // MARK: - Sheet

    private var sheetBody: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Close", systemImage: "xmark.circle.fill") { dismiss() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(DS.Color.textTertiary)
            }
            .padding([.top, .horizontal], DS.Spacing.md)

            ScrollView {
                pageSections
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.lg)
            }

            Divider()

            HStack {
                Button("Delete", role: .destructive) {
                    store.delete(word); dismiss()
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { store.update(word); dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(DS.Spacing.lg)
        }
        .frame(width: 520, height: 680)
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
                Text(word.term)
                    .font(DS.Typography.wordDisplayLarge)
                    .foregroundStyle(DS.Color.textPrimary)
                    .textSelection(.enabled)
                SpeakButton(text: word.term, size: 15, language: language)
                if let ipa = FillField.pronunciation.value(in: word) {
                    Text(ipa)
                        .font(DS.Typography.caption.monospaced())
                        .foregroundStyle(DS.Color.textSecondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
                Spacer(minLength: DS.Spacing.sm)
                // v19 S3: write a sentence with it — practice, the schedule stays.
                Button { showWriting = true } label: {
                    Label("Write a Sentence", systemImage: "pencil.line")
                }
                .buttonStyle(.dsQuiet)
                .help("Use this word in a sentence of your own; the AI corrects it")
            }
            if let definition {
                Text(definition)
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Color.textSecondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
            summaryLine
        }
    }

    /// v18 S5: the word at a glance — level, status, memory, and where it
    /// came from when that's worth saying (Kindle, another language).
    private var summaryLine: some View {
        HStack(spacing: DS.Spacing.sm) {
            if let cefr = word.cefrLevel.flatMap(CEFRLevel.init) {
                Text(word.cefrIsAuto ? "\(cefr.rawValue) · \(String(localized: "estimated"))" : cefr.rawValue)
                    .font(DS.Typography.caption.weight(.bold))
                    .foregroundStyle(cefr.badgeColor)
                    .padding(.horizontal, DS.Spacing.sm)
                    .padding(.vertical, DS.Spacing.hairline)
                    .background(cefr.badgeColor.opacity(0.12), in: Capsule())
                    .help(word.cefrIsAuto ? Text("Level estimated automatically") : Text("CEFR level"))
            }
            WordStatusBadge(status: WordStatus.of(current))
            if let recall = WordPageModel.recallNow(current) {
                Text("Memory \(Int((recall * 100).rounded()))% · \(RecallStrength(recall).title)")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textSecondary)
            }
            if word.hasTag(KindleVocabulary.deckName) {
                Text("Kindle")
                    .font(DS.Typography.caption2.weight(.semibold))
                    .foregroundStyle(DS.Color.kindle)
                    .padding(.horizontal, DS.Spacing.xs)
                    .padding(.vertical, DS.Spacing.hairline)
                    .background(DS.Color.kindle.opacity(0.12), in: Capsule())
                    .help("Imported from your Kindle")
            }
            if let other = word.language.flatMap(Language.init), other != Language.storedTarget {
                Text("\(other.flag) \(other.nativeName)")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textSecondary)
            }
        }
        .lineLimit(1)
    }

    // MARK: - Card (v15 S1)

    /// What the review card shows, field by field, with where each came
    /// from. Empty fields can be filled here; a filled one can be edited,
    /// filled again or removed from its context menu.
    private var cardSection: some View {
        // What "Fill Missing" fills: examples and the memory hook are asked
        // for one by one ("Fill Again" on their row).
        let empty = Self.cardFields.filter { FillField.defaultSelection.contains($0) && $0.isMissing(in: word) }.count
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Spacing.sm) {
                Text("CARD").dsOverlineLabel()
                Spacer()
                if empty > 0 {
                    Text(empty == 1 ? String(localized: "1 field empty") : String(localized: "\(empty) fields empty"))
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                }
                Button {
                    NSWorkspace.shared.open(Self.dictionaryURL(for: word.term))
                } label: {
                    Label("Open in Dictionary", systemImage: "character.book.closed")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Open in Dictionary")
                .accessibilityLabel("Open in Dictionary")
                if enricher != nil && empty > 0 && nothingMoreFound {
                    Text("Nothing more found")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                        .help("The dictionary and the models had nothing for the empty fields. You can type them in from the field's menu.")
                } else if enricher != nil && empty > 0 {
                    Button {
                        fillMissing()
                    } label: {
                        if isFilling {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Fill Missing")
                        }
                    }
                    // v18 S5: the card's quiet button family, with its key.
                    .buttonStyle(.dsQuiet)
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                    .help("Fill Missing (⇧⌘F)")
                    .disabled(isFilling)
                }
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)

            ForEach(shownCardFields) { field in
                Divider()
                cardRow(field)
            }
        }
        .dsCard(padding: nil)
    }

    @ViewBuilder
    private func cardRow(_ field: FillField) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
            Text(field.localizedTitle)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.textTertiary)
                .frame(width: 96, alignment: .leading)
            if editingField == field {
                TextField(field.localizedTitle, text: $editText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .onSubmit { commitEdit() }
                    // v18 S5: Esc leaves the field as it was.
                    .onExitCommand {
                        editingField = nil
                        focusedField = field
                    }
                Button("Done") { commitEdit() }
                    .controlSize(.small)
            } else {
                Group {
                    if let value = field.value(in: word) {
                        Text(value)
                            .font(field == .pronunciation ? DS.Typography.callout.monospaced() : DS.Typography.callout)
                            .foregroundStyle(DS.Color.textPrimary)
                            .lineLimit(4)
                            .textSelection(.enabled)
                    } else {
                        Text(emptyText(for: field))
                            .font(DS.Typography.callout.italic())
                            .foregroundStyle(DS.Color.textTertiary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let source = word.source(of: field), !field.isMissing(in: word) {
                    SourceChip(source: source)
                }
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
        .contentShape(Rectangle())
        // v18 S5: Tab walks the fields; Return edits the one in focus.
        .focusable(editingField != field)
        .focused($focusedField, equals: field)
        .onKeyPress(.return) {
            guard field != .level, editingField != field else { return .ignored }
            beginEdit(field)
            return .handled
        }
        .contextMenu {
            if field != .level {
                Button("Edit") { beginEdit(field) }
            }
            if enricher != nil {
                Button("Fill Again") { refill(field) }
            }
            if !field.isMissing(in: word) {
                Divider()
                Button("Remove", role: .destructive) { remove(field) }
            }
        }
    }

    private func emptyText(for field: FillField) -> String {
        if field == .examples && !word.sentence.isEmpty {
            return String(localized: "Empty. The card shows the sentence from your book.")
        }
        return String(localized: "Empty")
    }

    /// `dict://` opens Dictionary at the word — the whole entry the card
    /// only takes two senses from.
    static func dictionaryURL(for term: String) -> URL {
        let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? term
        return URL(string: "dict://\(encoded)") ?? URL(string: "dict://")!
    }

    private func fillMissing() {
        guard let enricher else { return }
        isFilling = true
        let emptyBefore = FillField.allCases.filter { $0.isMissing(in: word) }.count
        Task {
            await enricher.fill(wordID: word.id, allowProvider: fillUsesProvider)
            mergeFilledFields()
            nothingMoreFound = FillField.allCases.filter { $0.isMissing(in: word) }.count == emptyBefore
            isFilling = false
        }
    }

    private func refill(_ field: FillField) {
        guard let enricher else { return }
        clearLocally(field)
        isFilling = true
        Task {
            await enricher.refill(field, wordID: word.id, allowProvider: fillUsesProvider)
            mergeFilledFields()
            isFilling = false
        }
    }

    private func remove(_ field: FillField) {
        clearLocally(field)
    }

    private func clearLocally(_ field: FillField) {
        nothingMoreFound = false
        if field == .level {
            word.cefrLevel = nil
            word.cefrIsAuto = false
        } else if let module = field.module {
            word.llmOutputs[module.rawValue] = nil
        }
        word.fieldSources[field.rawValue] = nil
    }

    /// The fill writes to the store; this page edits a copy until Save, so
    /// fields the fill found are brought over — only into fields that are
    /// still empty here.
    private func mergeFilledFields() {
        guard let stored = store.word(withID: word.id) else { return }
        for field in FillField.allCases where field.isMissing(in: word) && !field.isMissing(in: stored) {
            if field == .level {
                word.cefrLevel = stored.cefrLevel
                word.cefrIsAuto = stored.cefrIsAuto
            } else if let module = field.module {
                word.llmOutputs[module.rawValue] = stored.llmOutputs[module.rawValue]
            }
            word.fieldSources[field.rawValue] = stored.fieldSources[field.rawValue]
        }
    }

    private func beginEdit(_ field: FillField) {
        editText = field.value(in: word) ?? ""
        editingField = field
    }

    /// What you type is yours: it loses the "filled from" mark.
    private func commitEdit() {
        guard let field = editingField, let module = field.module else { editingField = nil; return }
        let text = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        word.llmOutputs[module.rawValue] = text.isEmpty ? nil : text
        word.fieldSources[field.rawValue] = nil
        editingField = nil
        nothingMoreFound = false
    }


    // MARK: - Details

    var detailsSection: some View {
        DisclosureGroup(isExpanded: $showDetails) {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("TAGS / DECKS").dsOverlineLabel()
                    TagEditorView(tags: $word.tags, suggestions: store.allTags)
                }

                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("NOTES").dsOverlineLabel()
                    TextEditor(text: $word.notes)
                        .font(DS.Typography.callout)
                        .frame(minHeight: 64, maxHeight: 120)
                        .scrollContentBackground(.hidden)
                        .padding(DS.Spacing.sm)
                        .background(DS.Color.surfaceInset)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
                }

                if word.llmOutputs.keys.contains(where: { key in
                    ModuleType(rawValue: key) != nil && !Self.cardFields.contains { $0.module?.rawValue == key }
                }) {
                    savedOutputs
                }

                metadataSection
            }
            .padding(.top, DS.Spacing.sm)
        } label: {
            Text("Details")
                .font(DS.Typography.label)
                .foregroundStyle(DS.Color.textSecondary)
        }
    }

    private var savedOutputs: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("SAVED OUTPUTS").dsOverlineLabel()
            // The card's own fields are in the Card section above.
            ForEach(ModuleType.allCases.filter { module in
                word.llmOutputs[module.rawValue] != nil && !Self.cardFields.contains { $0.module == module }
            }) { module in
                let value = word.llmOutputs[module.rawValue] ?? ""
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    HStack(spacing: DS.Spacing.xs) {
                        Circle()
                            .fill(module.accentColor)
                            .frame(width: 5, height: 5)
                        Text(module.title)
                            .font(DS.Typography.caption.weight(.semibold))
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                    Text(value.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textPrimary)
                        .textSelection(.enabled)
                }
                .padding(DS.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.Color.surfaceInset)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
            }
            // v18 S3: your own modules' answers, under the name saved with them.
            ForEach(CustomPrompt.savedAnswers(in: word.llmOutputs, modules: CustomModuleStore.shared.modules)) { answer in
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: CustomModuleStore.shared.module(answer.id)?.icon ?? "sparkles")
                            .font(DS.Typography.icon(8, weight: .semibold))
                            .foregroundStyle(DS.Color.accent)
                        Text(answer.title)
                            .font(DS.Typography.caption.weight(.semibold))
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                    Text(InspectorView.markdown(answer.body.trimmingCharacters(in: .whitespacesAndNewlines)))
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textPrimary)
                        .textSelection(.enabled)
                }
                .padding(DS.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.Color.surfaceInset)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
            }
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text("METADATA").dsOverlineLabel()
            metaRow("Mode",   value: word.mode)
            metaRow("Domain", value: word.domain)
            metaRow("Saved",  value: Self.dateFormatter.string(from: word.savedAt))
            if let lastReviewedAt = word.lastReviewedAt {
                metaRow("Reviewed", value: Self.dateFormatter.string(from: lastReviewedAt))
            }
        }
    }

    private func metaRow(_ label: LocalizedStringKey, value: String) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            Text(label)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.textTertiary)
                .frame(width: 64, alignment: .trailing)
            Text(value)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.textPrimary)
                .textSelection(.enabled)
        }
    }
}

