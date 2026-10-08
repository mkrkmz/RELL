//
//  WordEnricher.swift
//  Reader for Language Learner
//
//  Fills the empty fields of saved words' cards (Roadmap v15 Sprint 1):
//  the meaning in your language, the definition in the language you study,
//  the pronunciation, the level and, if asked, examples. Each field is
//  taken from the cheapest source that gives a usable answer — the macOS
//  dictionary, then Apple's on-device model, then the configured provider —
//  and is written only while the field is still empty.
//
//  Three ways in: "Fill Missing" over the word list (a bulk run with
//  progress and Stop, the CEFR estimator's pattern), one word from its row
//  or its page, and a quiet fill right after a word is saved. Approved
//  decision 1: the save-time fill never reaches a cloud provider — a server
//  on this Mac at most; the cloud is used only when you press the button.
//

import Foundation
import os

// MARK: - Engine

/// One question to a model.
struct FillRequest: Equatable {
    let field: FillField
    let term: String
    let sentence: String
    let native: Language
    let target: Language

    /// The language the answer must be written in.
    var answerLanguage: Language { field == .meaning ? native : target }
}

struct FillResult: Equatable {
    let field: FillField
    let value: String
    let source: FillSource
}

/// What a fill can draw on. `WordEnricher` builds the live set; tests pass
/// fakes.
struct FillBackends {
    /// The raw system dictionary entry for a term.
    var dictionary: (String) -> String?
    /// Apple's on-device model, when it's on and speaks both languages.
    var onDevice: ((FillRequest) async -> String?)?
    /// The configured provider, when this fill may use it.
    var provider: (name: String, ask: (FillRequest) async -> String?)?
    /// The CEFR estimate and where it came from.
    var level: ((String) async -> FillResult?)?
}

@MainActor
enum WordFillEngine {
    /// Fills `fields` that are empty on `word`, field by field, reporting
    /// each value as soon as it's found. Stops between steps on cancellation.
    static func fill(
        _ word: SavedWord,
        fields: Set<FillField>,
        backends: FillBackends,
        native: Language,
        onResult: (FillResult) -> Void
    ) async {
        let target = word.language.flatMap(Language.init(rawValue:)) ?? Language.storedTarget
        let wanted = FillField.allCases.filter { fields.contains($0) && $0.isMissing(in: word) }
        guard !wanted.isEmpty else { return }

        let fromDictionary = dictionaryAnswer(
            for: word.term, raw: backends.dictionary(word.term), native: native, target: target
        )

        for field in wanted {
            guard !Task.isCancelled else { return }
            if let value = fromDictionary[field] {
                onResult(FillResult(field: field, value: value, source: .dictionary))
                continue
            }
            switch field {
            case .pronunciation:
                continue  // the models' IPA isn't trusted (v12 spike)
            case .level:
                if let result = await backends.level?(word.term) { onResult(result) }
            case .meaning, .definition, .examples:
                let request = FillRequest(field: field, term: word.term, sentence: word.sentence, native: native, target: target)
                if let ask = backends.onDevice,
                   let value = await ask(request).flatMap({ accept($0, request) }) {
                    onResult(FillResult(field: field, value: value, source: .onDevice))
                } else if !Task.isCancelled, let provider = backends.provider,
                          let value = await provider.ask(request).flatMap({ accept($0, request) }) {
                    onResult(FillResult(field: field, value: value, source: .provider(provider.name)))
                }
            }
        }
    }

    /// What the dictionary entry can fill: the meaning or the definition,
    /// depending on the language the entry is written in, and the
    /// pronunciation when the entry is for this very form.
    static func dictionaryAnswer(for term: String, raw: String?, native: Language, target: Language) -> [FillField: String] {
        guard let raw, let entry = DictionaryEntry(raw: raw) else { return [:] }
        var answer: [FillField: String] = [:]
        if let senses = entry.briefSenses, native != target {
            switch SystemDictionary.language(of: raw, headword: entry.headword.isEmpty ? term : entry.headword) {
            case native?: answer[.meaning] = senses
            case target?: answer[.definition] = senses
            default: break
            }
        }
        answer[.pronunciation] = entry.pronunciation(for: term)
        return answer
    }

    private static func accept(_ raw: String, _ request: FillRequest) -> String? {
        FillValidator.accept(raw, term: request.term, language: request.answerLanguage, field: request.field)
    }
}

// MARK: - Service

@MainActor
@Observable
final class WordEnricher {

    /// A bulk run, live or finished.
    struct Run: Equatable {
        var total: Int
        var fields: Set<FillField>
        var completed = 0
        var currentTerm = ""
        var tally: [FillField: [FillSource.Kind: Int]] = [:]
        var isFinished = false
        var wasStopped = false

        var filledCount: Int { tally.values.reduce(0) { $0 + $1.values.reduce(0, +) } }

        func count(_ field: FillField, _ kind: FillSource.Kind) -> Int { tally[field]?[kind] ?? 0 }
    }

    /// How far the provider may be used.
    enum ProviderUse { case never, onThisMac, any }

    private(set) var run: Run?
    var isRunning: Bool { run.map { !$0.isFinished } ?? false }

    private let store: SavedWordsStore
    private let cefrEstimator: CEFREstimator?
    /// One model request at a time: a local server has one GPU context,
    /// and this is background work next to the inspector.
    @ObservationIgnored private let gate = AsyncLimiter(limit: 1)
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Tests replace the live sources.
    @ObservationIgnored var backendsOverride: ((ProviderUse) -> FillBackends)?

    init(store: SavedWordsStore, cefrEstimator: CEFREstimator?, observesSaves: Bool = true) {
        self.store = store
        self.cefrEstimator = cefrEstimator
        guard observesSaves else { return }
        NotificationCenter.default.addObserver(forName: .savedWordAdded, object: nil, queue: .main) { [weak self] note in
            guard let id = note.object as? UUID else { return }
            Task { @MainActor [weak self] in self?.fillAfterSave(wordID: id) }
        }
    }

    // MARK: Counts

    func missingCount(_ field: FillField, in ids: Set<UUID>? = nil) -> Int {
        words(in: ids).count { field.isMissing(in: $0) }
    }

    func wordsMissingAny(_ fields: Set<FillField>, in ids: Set<UUID>? = nil) -> Int {
        words(in: ids).count { word in fields.contains { $0.isMissing(in: word) } }
    }

    func emptyFieldCount(_ fields: Set<FillField>, in ids: Set<UUID>? = nil) -> Int {
        fields.reduce(0) { $0 + missingCount($1, in: ids) }
    }

    private func words(in ids: Set<UUID>?) -> [SavedWord] {
        guard let ids else { return store.words }
        return store.words.filter { ids.contains($0.id) }
    }

    // MARK: Bulk run

    func start(fields: Set<FillField>, allowProvider: Bool, wordIDs: Set<UUID>? = nil) {
        guard !isRunning else { return }
        let targets = words(in: wordIDs).filter { word in fields.contains { $0.isMissing(in: word) } }.map(\.id)
        guard !targets.isEmpty else { return }
        let backends = backends(allowProvider ? .any : .never)
        let native = Language.storedNative
        run = Run(total: targets.count, fields: fields)

        task = Task { [weak self] in
            for id in targets {
                guard let self, !Task.isCancelled else { break }
                guard let word = self.store.word(withID: id) else { self.run?.completed += 1; continue }
                self.run?.currentTerm = word.term
                await WordFillEngine.fill(word, fields: fields, backends: backends, native: native) { result in
                    if self.store.fill(result.field, with: result.value, source: result.source, forWordID: id) {
                        self.run?.tally[result.field, default: [:]][result.source.kind, default: 0] += 1
                    }
                }
                if !Task.isCancelled { self.run?.completed += 1 }
            }
            self?.run?.isFinished = true
            self?.run?.currentTerm = ""
            self?.task = nil
            self?.hideStripForWhatsLeft()
        }
    }

    /// Stops after the field in flight; everything filled so far stays.
    func stop() {
        task?.cancel()
        task = nil
        run?.wasStopped = true
        run?.isFinished = true
        run?.currentTerm = ""
        hideStripForWhatsLeft()
    }

    /// After a run, the words still without a meaning are ones the sources
    /// couldn't fill; the list's strip stays away until a new one comes.
    private func hideStripForWhatsLeft() {
        UserDefaults.standard.set(missingCount(.meaning), forKey: StorageKey.fillStripHiddenAtCount)
    }

    /// Forgets a finished run's summary.
    func clearFinishedRun() {
        if run?.isFinished == true { run = nil }
    }

    // MARK: One word

    /// Fills one word's empty fields — its row's menu and its page.
    func fill(wordID: UUID, fields: Set<FillField> = FillField.defaultSelection, allowProvider: Bool) async {
        guard let word = store.word(withID: wordID) else { return }
        let backends = backends(allowProvider ? .any : .never)
        await WordFillEngine.fill(word, fields: fields, backends: backends, native: Language.storedNative) { result in
            store.fill(result.field, with: result.value, source: result.source, forWordID: wordID)
        }
    }

    /// "Fill again": empties the field, then fills it.
    func refill(_ field: FillField, wordID: UUID, allowProvider: Bool) async {
        store.clear(field, forWordID: wordID)
        await fill(wordID: wordID, fields: [field], allowProvider: allowProvider)
    }

    /// Right after a save: the dictionary, the on-device model and a server
    /// on this Mac — never the cloud. The level is the CEFR estimator's job
    /// at save time already.
    private func fillAfterSave(wordID: UUID) {
        guard UserDefaults.standard.object(forKey: StorageKey.fillOnSave) as? Bool ?? true,
              let word = store.word(withID: wordID) else { return }
        let fields = FillField.defaultSelection.subtracting([.level])
        let backends = backends(.onThisMac)
        Task(priority: .utility) { [weak self] in
            guard let self else { return }
            await WordFillEngine.fill(word, fields: fields, backends: backends, native: Language.storedNative) { result in
                self.store.fill(result.field, with: result.value, source: result.source, forWordID: wordID)
            }
        }
    }

    // MARK: Dictionary on the card

    /// The dictionary's answer for a card whose back has nothing to show —
    /// read live, not stored (approved decision 3). Nil when the entry is
    /// in neither of your languages.
    func dictionaryPreview(for word: SavedWord) -> FillResult? {
        let target = word.language.flatMap(Language.init(rawValue:)) ?? Language.storedTarget
        let answer = WordFillEngine.dictionaryAnswer(
            for: word.term, raw: SystemDictionary.rawDefinition(for: word.term),
            native: Language.storedNative, target: target
        )
        if let meaning = answer[.meaning] { return FillResult(field: .meaning, value: meaning, source: .dictionary) }
        if let definition = answer[.definition] { return FillResult(field: .definition, value: definition, source: .dictionary) }
        return nil
    }

    /// "Add to Card": keeps the previewed answer and the pronunciation.
    func addDictionaryAnswer(to wordID: UUID) {
        guard let word = store.word(withID: wordID) else { return }
        let target = word.language.flatMap(Language.init(rawValue:)) ?? Language.storedTarget
        let answer = WordFillEngine.dictionaryAnswer(
            for: word.term, raw: SystemDictionary.rawDefinition(for: word.term),
            native: Language.storedNative, target: target
        )
        for (field, value) in answer {
            store.fill(field, with: value, source: .dictionary, forWordID: wordID)
        }
    }

    // MARK: Live sources

    private func backends(_ use: ProviderUse) -> FillBackends {
        if let backendsOverride { return backendsOverride(use) }
        return FillBackends(
            dictionary: { SystemDictionary.rawDefinition(for: $0) },
            onDevice: onDeviceAsk(),
            provider: providerAsk(use),
            level: levelAsk(use)
        )
    }

    private func onDeviceAsk() -> ((FillRequest) async -> String?)? {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *),
              AppleOnDevice.isEnabled, AppleOnDevice.isModelAvailable,
              AppleOnDevice.supports(Language.storedNative), AppleOnDevice.supports(Language.storedTarget)
        else { return nil }
        let gate = gate
        return { request in
            await Self.ask(AppleOnDeviceClient(), request, gate: gate, label: "on-device")
        }
        #else
        return nil
        #endif
    }

    private func providerAsk(_ use: ProviderUse) -> (name: String, ask: (FillRequest) async -> String?)? {
        let configuration = LLMConfiguration()
        switch use {
        case .never: return nil
        case .onThisMac: guard Self.runsOnThisMac(configuration) else { return nil }
        case .any: break
        }
        let provider = configuration.makeProvider()
        let gate = gate
        return (configuration.providerType.localizedTitle, { request in
            await Self.ask(provider, request, gate: gate, label: "provider")
        })
    }

    private func levelAsk(_ use: ProviderUse) -> ((String) async -> FillResult?)? {
        guard let cefrEstimator else { return nil }
        let onDevice = AppleOnDevice.currentRoute(for: nil) == .appleOnDevice
        let source: FillSource
        if onDevice {
            source = .onDevice
        } else {
            let configuration = LLMConfiguration()
            switch use {
            case .never: return nil
            case .onThisMac: guard Self.runsOnThisMac(configuration) else { return nil }
            case .any: break
            }
            source = .provider(configuration.providerType.localizedTitle)
        }
        return { term in
            guard let level = await cefrEstimator.estimate(term: term) else { return nil }
            return FillResult(field: .level, value: level.rawValue, source: source)
        }
    }

    /// A local server on this Mac, not a cloud model reached through it
    /// (Ollama's `…-cloud` models run remotely).
    static func runsOnThisMac(_ configuration: LLMConfiguration) -> Bool {
        runsOnThisMac(type: configuration.providerType, serverURL: configuration.serverURL, model: configuration.model)
    }

    static func runsOnThisMac(type: LLMProviderType, serverURL: String, model: String) -> Bool {
        guard type == .lmStudio || type == .ollama,
              let host = URL(string: serverURL)?.host?.lowercased(),
              ["127.0.0.1", "localhost", "::1", "[::1]"].contains(host)
        else { return false }
        return !model.lowercased().contains("cloud")
    }

    private static func ask(_ provider: any LLMProvider, _ request: FillRequest, gate: AsyncLimiter, label: String) async -> String? {
        guard let module = request.field.module else { return nil }
        await gate.acquire()
        defer { gate.release() }
        guard !Task.isCancelled else { return nil }
        let context = request.sentence.isEmpty ? nil : String(request.sentence.prefix(400))
        do {
            return try await provider.chat(
                system: module.systemPrompt(customPreamble: "", nativeLanguage: request.native, targetLanguage: request.target),
                user: module.userPrompt(term: request.term, mode: .word, detail: .short, context: context,
                                        nativeLanguage: request.native, targetLanguage: request.target),
                temperature: module.recommendedTemperature,
                maxTokens: module.recommendedMaxTokens(mode: .word, detail: .short),
                topP: 0.9
            )
        } catch {
            AppLogger.llm.info("Fill (\(label, privacy: .public)) failed for \(request.term, privacy: .private): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
