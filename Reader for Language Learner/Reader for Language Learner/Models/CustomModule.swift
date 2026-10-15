//
//  CustomModule.swift
//  Reader for Language Learner
//
//  Modules the reader writes (Roadmap v18 Sprint 3, approved mockup): a
//  name, an icon, a prompt with placeholders, where it runs (word, sentence
//  or both), the answer's language and length, and which engine answers.
//  They sit on the Inspector's card beside the built-in modules but stay
//  out of everything those are wired into — Fill Missing, the level
//  estimate, the special parsers, per-module settings. Kept in their own
//  file, which the daily backups include.
//

import Foundation
import os

nonisolated struct CustomModule: Codable, Identifiable, Equatable, Sendable {
    enum Scope: String, Codable, CaseIterable, Sendable { case word, sentence, both }
    enum AnswerLanguage: String, Codable, CaseIterable, Sendable { case target, native }
    enum Length: String, Codable, CaseIterable, Sendable { case short, long }
    enum Engine: String, Codable, CaseIterable, Sendable { case provider, apple }

    var id = UUID()
    var name: String
    var icon: String
    var prompt: String
    var scope: Scope = .word
    var answerIn: AnswerLanguage = .native
    var length: Length = .short
    var engine: Engine = .provider

    // MARK: Limits (approved: 20 modules, 2,000 characters)

    static let maxCount = 20
    static let maxPromptLength = 2_000

    var maxTokens: Int { length == .short ? 300 : 800 }

    func runs(on kind: CardKind) -> Bool {
        switch scope {
        case .word:     return kind == .word
        case .sentence: return kind == .sentence
        case .both:     return true
        }
    }

    /// The icons offered in the editor.
    static let icons = ["sparkles", "questionmark.bubble", "arrow.left.arrow.right", "face.smiling",
                        "pencil.line", "music.note", "star", "flag", "lightbulb", "theatermasks",
                        "graduationcap", "text.quote"]

    /// Where an answer is kept with a saved word, and its name beside it —
    /// so a deleted module's answers still show what they were.
    var outputKey: String { Self.outputKey(id) }
    static func outputKey(_ id: UUID) -> String { "custom.\(id.uuidString)" }
    static func titleKey(_ id: UUID) -> String { "custom.\(id.uuidString).title" }

    // MARK: Templates (approved mockup)

    static var templates: [CustomModule] {
        [
            CustomModule(name: String(localized: "Explain Like I'm Ten"), icon: "face.smiling",
                         prompt: "Explain the word {selection} to a ten-year-old. The sentence it came from: {sentence}. My level is {level}. Answer in {native} in at most three sentences.",
                         scope: .word, answerIn: .native, length: .short),
            CustomModule(name: String(localized: "Quiz Me"), icon: "questionmark.bubble",
                         prompt: "Ask me three short questions in {target} that make me use the word {selection}. Don't give the answers.",
                         scope: .word, answerIn: .target, length: .short),
            CustomModule(name: String(localized: "Formal / Casual"), icon: "arrow.left.arrow.right",
                         prompt: "Rewrite this sentence twice in {target}: once formal, once casual. Sentence: {selection}",
                         scope: .sentence, answerIn: .target, length: .long),
        ]
    }
}

// MARK: - Filling the placeholders

nonisolated enum CustomPrompt {
    /// What a placeholder stands for. Each has an English name and the
    /// Turkish one the Turkish editor inserts; both are understood.
    enum Placeholder: String, CaseIterable, Sendable {
        case selection, sentence, book, native, target, level

        var names: [String] {
            switch self {
            case .selection: return ["{selection}", "{seçim}"]
            case .sentence:  return ["{sentence}", "{cümle}"]
            case .book:      return ["{book}", "{kitap}"]
            case .native:    return ["{native}", "{ana dil}"]
            case .target:    return ["{target}", "{hedef dil}"]
            case .level:     return ["{level}", "{seviye}"]
            }
        }
    }

    /// The prompt with its placeholders filled. A line whose placeholder
    /// has no value (no sentence, no book) is left out whole, so the model
    /// never reads an empty "The sentence it came from: .".
    static func render(_ prompt: String, values: [Placeholder: String]) -> String {
        prompt.components(separatedBy: "\n").compactMap { line -> String? in
            var line = line
            for placeholder in Placeholder.allCases {
                for name in placeholder.names where line.contains(name) {
                    let value = values[placeholder]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if value.isEmpty { return nil }
                    line = line.replacingOccurrences(of: name, with: value)
                }
            }
            return line
        }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The system prompt around the reader's own: the answer's language,
    /// plain Markdown, no preamble.
    static func system(for module: CustomModule, native: Language, target: Language, preamble: String) -> String {
        let language = module.answerIn == .native ? native : target
        let base = "You help someone learning \(target.rawValue) while they read. Answer in \(language.rawValue). Use plain Markdown, no preamble, and stay brief."
        let trimmed = preamble.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? base : trimmed + "\n\n" + base
    }

    /// Part of the answer cache's key: editing the prompt or its settings
    /// never shows an answer to the old one.
    static func cacheTag(_ module: CustomModule) -> String {
        "\(module.id.uuidString)#\(stableHash(module))"
    }

    /// FNV-1a over the fields that shape the answer — stable across launches
    /// (`Hasher` is seeded per process).
    private static func stableHash(_ module: CustomModule) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in "\(module.prompt)|\(module.answerIn.rawValue)|\(module.length.rawValue)|\(module.engine.rawValue)".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}

// MARK: - Saved answers

/// One own-module answer kept with a saved word (or about to be exported).
nonisolated struct OwnModuleAnswer: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let body: String
}

extension CustomPrompt {
    /// The own-module answers among a saved word's outputs: the modules you
    /// still have first, in their order, then deleted ones under the name
    /// saved beside the answer.
    static func savedAnswers(in outputs: [String: String], modules: [CustomModule]) -> [OwnModuleAnswer] {
        let prefix = "custom."
        var answers: [OwnModuleAnswer] = []
        for (key, body) in outputs where key.hasPrefix(prefix) && !key.hasSuffix(".title") {
            guard let id = UUID(uuidString: String(key.dropFirst(prefix.count))),
                  !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let title = modules.first { $0.id == id }?.name
                ?? outputs[CustomModule.titleKey(id)]
                ?? String(localized: "Own module")
            answers.append(OwnModuleAnswer(id: id, title: title, body: body))
        }
        let order = Dictionary(uniqueKeysWithValues: modules.enumerated().map { ($1.id, $0) })
        return answers.sorted { a, b in
            switch (order[a.id], order[b.id]) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.title.localizedStandardCompare(b.title) == .orderedAscending
            }
        }
    }
}

// MARK: - Store

@MainActor
@Observable
final class CustomModuleStore {
    /// Off the main actor: on macOS 15 a main-actor deinit run outside a
    /// task crashes when it releases another one (v16 S0, CI crash reports).
    nonisolated deinit {}

    static let fileName = "custom_modules.json"
    static let shared = CustomModuleStore()

    private(set) var modules: [CustomModule] = []
    @ObservationIgnored private let fileURL: URL?

    init(fileURL: URL? = FileManager.default.rellAppSupportDirectory()?.appendingPathComponent(CustomModuleStore.fileName)) {
        self.fileURL = fileURL
        if let fileURL {
            modules = RELLJSONStore.load([CustomModule].self, from: fileURL, storeName: "CustomModuleStore", defaultValue: [])
        }
    }

    var canAdd: Bool { modules.count < CustomModule.maxCount }

    func module(_ id: UUID) -> CustomModule? {
        modules.first { $0.id == id }
    }

    /// Adds a new module — onto the end of the cards it runs on (approved:
    /// you made it to use it; what doesn't fit moves to •••).
    @discardableResult
    func add(_ module: CustomModule, defaults: UserDefaults = .standard) -> Bool {
        guard canAdd else { return false }
        var module = module
        module.prompt = String(module.prompt.prefix(CustomModule.maxPromptLength))
        modules.append(module)
        persist()
        for kind in CardKind.allCases where module.runs(on: kind) {
            let pinned = InspectorCardLayout.load(kind, defaults: defaults, customs: modules)
            InspectorCardLayout.save(InspectorCardLayout.pin(.custom(module.id), in: pinned), for: kind, defaults: defaults)
        }
        return true
    }

    func update(_ module: CustomModule) {
        guard let index = modules.firstIndex(where: { $0.id == module.id }) else { return }
        var module = module
        module.prompt = String(module.prompt.prefix(CustomModule.maxPromptLength))
        modules[index] = module
        persist()
        NotificationCenter.default.post(name: .inspectorCardChanged, object: nil)
    }

    /// Removes the module; answers already saved with words keep its name.
    func delete(_ id: UUID) {
        modules.removeAll { $0.id == id }
        persist()
        NotificationCenter.default.post(name: .inspectorCardChanged, object: nil)
    }

    private func persist() {
        guard let fileURL else { return }
        do {
            try RELLJSONStore.save(modules, to: fileURL, storeName: "CustomModuleStore")
        } catch {
            AppLogger.persistence.error("CustomModuleStore save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
