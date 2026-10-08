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
    @Environment(WordEncounterStore.self) private var encounterStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @Environment(WordEnricher.self) private var enricher: WordEnricher?
    @AppStorage(StorageKey.fillUsesProvider) private var fillUsesProvider = true

    @State private var showAllEncounters = false
    @State private var isFilling = false
    @State private var editingField: FillField?
    @State private var editText = ""
    @State private var showDetails = false

    /// Encounters shown before "Show all".
    private static let collapsedEncounterCount = 6

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private var language: Language {
        word.language.flatMap(Language.init(rawValue:)) ?? Language.storedTarget
    }

    /// The meaning in your language, else the definition — the hero's line.
    private var definition: String? {
        SavedWordRow.oneLineMeaning(of: word).map { MarkdownUtils.sanitizeLLMOutput($0) }
    }

    /// Fields the card section lists, in card order.
    private static let cardFields: [FillField] = [.meaning, .definition, .pronunciation, .examples, .level]

    var body: some View {
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
                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    hero
                    cardSection
                    memoryCard
                    encountersSection
                    if !word.sentence.isEmpty { savedContext }
                    detailsSection
                }
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
                Spacer()
                if let cefr = word.cefrLevel {
                    Text(cefr)
                        .font(DS.Typography.caption.weight(.bold))
                        .foregroundStyle(CEFRLevel(rawValue: cefr)?.badgeColor ?? DS.Color.textSecondary)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, DS.Spacing.xxs)
                        .background(
                            (CEFRLevel(rawValue: cefr)?.badgeColor ?? DS.Color.textSecondary).opacity(0.12),
                            in: Capsule()
                        )
                        .help(word.cefrIsAuto ? Text("Level estimated automatically") : Text("CEFR level"))
                }
                Label(word.masteryLevel.localizedTitle, systemImage: word.masteryLevel.icon)
                    .font(DS.Typography.caption.weight(.semibold))
                    .foregroundStyle(word.masteryLevel.color)
            }
            if let definition {
                Text(definition)
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Color.textSecondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - Card (v15 S1)

    /// What the review card shows, field by field, with where each came
    /// from. Empty fields can be filled here; a filled one can be edited,
    /// filled again or removed from its context menu.
    private var cardSection: some View {
        let empty = Self.cardFields.filter { $0 != .examples && $0.isMissing(in: word) }.count
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
                if enricher != nil && empty > 0 {
                    Button {
                        fillMissing()
                    } label: {
                        if isFilling {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Fill Missing")
                        }
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .disabled(isFilling)
                }
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)

            ForEach(Self.cardFields) { field in
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
        Task {
            await enricher.fill(wordID: word.id, allowProvider: fillUsesProvider)
            mergeFilledFields()
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
    }

    // MARK: - Memory

    private var memoryCard: some View {
        HStack(spacing: DS.Spacing.lg) {
            if let recall = WordPageModel.recallNow(word) {
                Gauge(value: recall) {
                    EmptyView()
                } currentValueLabel: {
                    Text(recall, format: .percent.precision(.fractionLength(0)))
                        .font(DS.Typography.statNumber(12))
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(recall >= 0.8 ? DS.Color.success : recall >= 0.5 ? DS.Color.warning : DS.Color.danger)
                .accessibilityLabel(Text("Chance you remember it now"))

                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text("Chance you remember it now")
                        .font(DS.Typography.label)
                        .foregroundStyle(DS.Color.textPrimary)
                    nextReviewLine
                }
            } else {
                Image(systemName: "sparkle")
                    .font(DS.Typography.icon(20))
                    .foregroundStyle(DS.Color.accent)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text("Not reviewed yet")
                        .font(DS.Typography.label)
                        .foregroundStyle(DS.Color.textPrimary)
                    Text("Its first review will start tracking how well you remember it.")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .dsCard()
    }

    @ViewBuilder
    private var nextReviewLine: some View {
        if let next = word.nextReviewAt {
            if next <= Date() {
                Text("Due for review now")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.warning)
            } else {
                Text("Next review \(next, format: .relative(presentation: .named))")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
            }
        }
        Text("\(word.reviewCount) reviews · \(word.incorrectCount) missed")
            .font(DS.Typography.caption)
            .foregroundStyle(DS.Color.textTertiary)
    }

    // MARK: - Encounters

    private var encountersSection: some View {
        let encounters = encounterStore.encounters(for: word.id)
        let shown = showAllEncounters ? encounters : Array(encounters.prefix(Self.collapsedEncounterCount))
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack {
                Text("MET IN YOUR READING").dsOverlineLabel()
                Spacer()
                if let summary = WordPageModel.encounterSummary(encounters) {
                    Text(summary)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }
            if encounters.isEmpty {
                Text("Not met again yet. Pages you read from now on are checked for this word, and every sentence it turns up in is collected here.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(shown) { encounter in
                    EncounterRow(
                        encounter: encounter,
                        sentence: WordPageModel.emphasized(encounter.sentence, term: word.term, language: language),
                        isAvailable: DocumentJump.isAvailable(encounter.documentPath),
                        onOpen: { open(encounter) }
                    )
                }
                if encounters.count > Self.collapsedEncounterCount {
                    Button(showAllEncounters ? "Show fewer" : "Show all \(encounters.count)") {
                        withAnimation(DS.Animation.standard) { showAllEncounters.toggle() }
                    }
                    .buttonStyle(.link)
                    .font(DS.Typography.caption)
                }
            }
        }
    }

    private func open(_ encounter: WordEncounter) {
        let location = DocumentLocation(
            url: URL(fileURLWithPath: encounter.documentPath),
            location: encounter.location,
            isEPUB: encounter.isEPUB
        )
        DocumentJump.prepare(location)
        dismiss()
        openWindow(value: location.url)
        DocumentJump.announce(location)
    }

    // MARK: - Saved context

    private var savedContext: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text("WHERE YOU SAVED IT").dsOverlineLabel()
            Text(WordPageModel.emphasized(word.sentence, term: word.term, language: language))
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Color.textPrimary)
                .textSelection(.enabled)
            if let pdf = word.pdfFilename {
                Text(pdf + (word.pageNumber.map { " · \(String(localized: "p. \($0)"))" } ?? ""))
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
            }
        }
    }

    // MARK: - Details

    private var detailsSection: some View {
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

                if word.llmOutputs.keys.contains(where: { key in !Self.cardFields.contains { $0.module?.rawValue == key } }) {
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

/// One sentence the word turned up in, and where. Clicking opens the book
/// there; a document that's gone from disk shows the sentence but can't open.
private struct EncounterRow: View {
    let encounter: WordEncounter
    let sentence: AttributedString
    let isAvailable: Bool
    let onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(sentence)
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Color.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: encounter.isEPUB ? "book" : "doc.text")
                        .font(DS.Typography.icon(10))
                    Text(encounter.documentTitle)
                        .lineLimit(1)
                    Text("·")
                    Text(WordPageModel.locationLabel(encounter))
                    Text("·")
                    Text(encounter.date, format: .relative(presentation: .named))
                    if encounter.occurrences > 1 {
                        Text("· ×\(encounter.occurrences)")
                    }
                    Spacer(minLength: 0)
                    if isAvailable && isHovered {
                        Image(systemName: "arrow.up.forward")
                            .font(DS.Typography.icon(10, weight: .semibold))
                    }
                }
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.textTertiary)
            }
            .padding(DS.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovered && isAvailable ? DS.Color.hoverOverlay : DS.Color.surfaceInset)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .onHover { isHovered = $0 }
        .help(isAvailable ? Text("Open at this page") : Text("This document is no longer on this Mac"))
    }
}
