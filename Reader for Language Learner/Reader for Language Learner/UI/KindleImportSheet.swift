//
//  KindleImportSheet.swift
//  Reader for Language Learner
//
//  "Import From Kindle" (Roadmap v15 Sprint 4): finds a connected Kindle
//  (or takes a vocab.db you choose), shows what's new by book, and saves
//  the chosen words — each with the sentence it was looked up in — into
//  the Kindle deck, then fills their cards in the background. The device
//  is only read (`KindleVocabulary`).
//

import SwiftUI
import UniformTypeIdentifiers

struct KindleImportSheet: View {
    var store: SavedWordsStore
    var enricher: WordEnricher?

    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case looking
        case noKindle
        case loaded(KindleVocabulary.Plan, source: String)
        case failed(String)
        case imported(Int, filling: Bool)
    }

    @State private var phase: Phase = .looking
    @State private var selectedBooks: Set<String> = []
    @State private var includeMastered = false
    @State private var fillAfter = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text("Import From Kindle")
                    .font(DS.Typography.headline)
                Text(subtitle)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding([.top, .horizontal], DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.sm)

            content
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.md)

            Divider()
            footer
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.md)
        }
        .frame(width: 480)
        .task { load(KindleVocabulary.connectedDatabase()) }
    }

    private var subtitle: String {
        switch phase {
        case .looking:
            return String(localized: "Looking for a connected Kindle…")
        case .noKindle:
            return String(localized: "Connect your Kindle with a USB cable, or choose a vocab.db file.")
        case .loaded(_, let source):
            return source
        case .failed(let message):
            return message
        case .imported:
            return String(localized: "Your Kindle wasn't changed.")
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .looking:
            ProgressView().frame(maxWidth: .infinity)
        case .noKindle, .failed:
            EmptyView()
        case .loaded(let plan, _):
            loaded(plan)
        case .imported(let count, let filling):
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(count == 1 ? String(localized: "1 word imported into the Kindle deck.")
                                : String(localized: "\(count) words imported into the Kindle deck."))
                    .font(DS.Typography.callout.weight(.semibold))
                if filling {
                    Text("Their meanings are being filled in; the progress shows above the word list.")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }
        }
    }

    private func loaded(_ plan: KindleVocabulary.Plan) -> some View {
        let mastered = plan.candidates.count { $0.isMastered && selectedBooks.contains($0.bookID ?? "") }
        return VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text(summary(plan))
                .font(DS.Typography.callout)
                .fixedSize(horizontal: false, vertical: true)

            if !plan.books.isEmpty {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    HStack {
                        Text("BOOKS").dsOverlineLabel()
                        Spacer()
                        Button(selectedBooks.count == plan.books.count ? String(localized: "Select None") : String(localized: "Select All")) {
                            selectedBooks = selectedBooks.count == plan.books.count ? [] : Set(plan.books.map(\.id))
                        }
                        .buttonStyle(.link)
                        .font(DS.Typography.caption)
                    }
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            ForEach(plan.books) { book in
                                Toggle(isOn: Binding(
                                    get: { selectedBooks.contains(book.id) },
                                    set: { on in if on { selectedBooks.insert(book.id) } else { selectedBooks.remove(book.id) } }
                                )) {
                                    HStack {
                                        Text(book.title).lineLimit(1).truncationMode(.middle)
                                        Spacer(minLength: DS.Spacing.sm)
                                        Text("\(book.wordCount)")
                                            .foregroundStyle(DS.Color.textSecondary)
                                            .monospacedDigit()
                                    }
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                        .padding(DS.Spacing.sm)
                    }
                    .frame(maxHeight: 220)
                    .dsCard(padding: nil, radius: DS.Radius.sm)
                }
            }

            if mastered > 0 {
                Toggle(String(localized: "Include the \(mastered) words marked as learned on Kindle"), isOn: $includeMastered)
                    .toggleStyle(.checkbox)
            }
            if enricher != nil {
                Toggle(isOn: $fillAfter) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Fill in their meanings right after")
                        Text("From the dictionary and the on-device model, in the background.")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Color.textTertiary)
                    }
                }
                .toggleStyle(.checkbox)
            }
        }
    }

    private func summary(_ plan: KindleVocabulary.Plan) -> String {
        var parts = [String(localized: "\(plan.candidates.count) new words in \(FillField.languageName(Language.storedTarget)).")]
        if plan.alreadySaved > 0 { parts.append(String(localized: "\(plan.alreadySaved) are already saved.")) }
        if plan.otherLanguage > 0 { parts.append(String(localized: "\(plan.otherLanguage) in other languages are left out.")) }
        return parts.joined(separator: " ")
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: DS.Spacing.sm) {
            switch phase {
            case .imported:
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            default:
                Button("Choose File…", action: chooseFile)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if case .loaded(let plan, _) = phase {
                    let count = plan.savedWords(books: selectedBooks, includeMastered: includeMastered).count
                    Button(count == 1 ? String(localized: "Import 1 Word") : String(localized: "Import \(count) Words")) {
                        importWords(plan)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(count == 0)
                }
            }
        }
    }

    // MARK: Actions

    private func load(_ database: URL?, chosen: Bool = false) {
        guard let database else { phase = .noKindle; return }
        do {
            let words = try KindleVocabulary.read(database)
            let plan = KindleVocabulary.Plan(words: words, existing: store.words, target: Language.storedTarget)
            selectedBooks = Set(plan.books.map(\.id))
            let source = chosen
                ? String(localized: "From \(database.lastPathComponent). The file is only read.")
                : String(localized: "From the Kindle connected to this Mac. It is only read, never changed.")
            phase = .loaded(plan, source: source)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "db") ?? .data]
        panel.canChooseDirectories = false
        panel.message = String(localized: "Choose vocab.db — on a Kindle it's in system/vocabulary.")
        if panel.runModal() == .OK, let url = panel.url {
            load(url, chosen: true)
        }
    }

    private func importWords(_ plan: KindleVocabulary.Plan) {
        let ids = store.addImported(plan.savedWords(books: selectedBooks, includeMastered: includeMastered))
        let filling = fillAfter && !ids.isEmpty && enricher.map { !$0.isRunning } == true
        if filling {
            enricher?.start(fields: FillField.defaultSelection, allowProvider: false, wordIDs: Set(ids))
        }
        phase = .imported(ids.count, filling: filling)
    }
}
