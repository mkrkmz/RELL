//
//  PromptEvaluationTests.swift
//  Reader for Language LearnerTests
//
//  Roadmap v19 Sprint 1: the modules' prompts are changed by measuring. A
//  fixed set of words and sentences — several meanings, phrasal verbs,
//  idioms, inflected forms, domain terms, false friends, book sentences,
//  three other study languages — runs through every module, and each answer
//  is saved with automatic checks: the right language, the format the app's
//  parsers read, cut off or not, a preamble, the length. Run once with the
//  old prompts and once with the new ones; scripts/prompt-report.py puts
//  the two side by side.
//
//  Runs on request only, against a model you choose (it talks to a real
//  server):
//
//    TEST_RUNNER_RELL_PROMPT_EVAL=1 \
//    TEST_RUNNER_RELL_EVAL_URL=http://127.0.0.1:11434 \
//    TEST_RUNNER_RELL_EVAL_MODEL=gemma4:31b-cloud \
//    TEST_RUNNER_RELL_EVAL_OUT=/path/to/eval-old.json \
//    xcodebuild test … -only-testing:"Reader for Language LearnerTests/PromptEvaluationTests"
//
//  Optional: RELL_EVAL_LIMIT (first N items), RELL_EVAL_CAPS_MODEL (the
//  model whose token limits apply, e.g. a small local one).
//

import NaturalLanguage
import XCTest
@testable import Reader_for_Language_Learner

/// One thing to ask about.
struct PromptEvalItem: Sendable {
    let id: String
    let term: String
    let context: String?
    let mode: ExplainMode
    let target: Language
    /// What a good answer must get right — for the person reading the report.
    let watch: String
}

enum PromptEvalSet {
    static let native: Language = .turkish
    static let level: CEFRLevel = .b1

    static let items: [PromptEvalItem] = [
        // Several meanings: the sentence decides.
        .init(id: "bank-river", term: "bank", context: "They sat on the bank of the river and watched the boats.", mode: .word, target: .english, watch: "kıyı, not a money bank"),
        .init(id: "fair-just", term: "fair", context: "The judge was fair to both sides.", mode: .word, target: .english, watch: "adil"),
        .init(id: "fair-event", term: "fair", context: "The fair came to town every August.", mode: .word, target: .english, watch: "panayır, fuar — same word, other sense"),
        .init(id: "run-manage", term: "runs", context: "She runs a small bookshop near the station.", mode: .word, target: .english, watch: "işletmek, not koşmak"),
        .init(id: "light-luggage", term: "light", context: "Travel light; you won't need much.", mode: .word, target: .english, watch: "az eşyayla"),
        // Phrasal verbs and idioms.
        .init(id: "put-up-with", term: "put up with", context: "I can't put up with the noise any longer.", mode: .word, target: .english, watch: "katlanmak"),
        .init(id: "gave-in", term: "gave in", context: "After hours of arguing, he finally gave in.", mode: .word, target: .english, watch: "pes etmek, boyun eğmek"),
        .init(id: "break-the-ice", term: "break the ice", context: "He told a joke to break the ice.", mode: .word, target: .english, watch: "buzları eritmek — an idiom, not literal"),
        .init(id: "under-the-weather", term: "under the weather", context: "I'm feeling a bit under the weather today.", mode: .word, target: .english, watch: "keyifsiz, biraz hasta"),
        // Inflected forms.
        .init(id: "overcame", term: "overcame", context: "She overcame her fear of water.", mode: .word, target: .english, watch: "overcome, yenmek"),
        .init(id: "ricocheted", term: "ricocheted", context: "The bullet ricocheted off the wall.", mode: .word, target: .english, watch: "sekmek"),
        .init(id: "fled", term: "fled", context: "The villagers fled the burning town.", mode: .word, target: .english, watch: "flee, kaçmak"),
        // Domain terms.
        .init(id: "consideration-legal", term: "consideration", context: "There is no binding contract without consideration.", mode: .word, target: .english, watch: "legal: bedel, karşılık — not düşünme"),
        .init(id: "liabilities", term: "liabilities", context: "The company's liabilities exceed its assets.", mode: .word, target: .english, watch: "borçlar, yükümlülükler"),
        // False friends for a Turkish reader.
        .init(id: "actual", term: "actual", context: "The actual cost was much higher than the estimate.", mode: .word, target: .english, watch: "gerçek — not aktüel/güncel"),
        .init(id: "sympathetic", term: "sympathetic", context: "She was sympathetic when I told her about my loss.", mode: .word, target: .english, watch: "anlayışlı, şefkatli — not sempatik"),
        .init(id: "eventually", term: "eventually", context: "Eventually, they found the way home.", mode: .word, target: .english, watch: "sonunda — not belki/muhtemelen"),
        .init(id: "sensible", term: "sensible", context: "It was a sensible decision.", mode: .word, target: .english, watch: "mantıklı — not hassas"),
        // Rare and literary; a word with no context.
        .init(id: "melancholy", term: "melancholy", context: "A melancholy silence filled the room.", mode: .word, target: .english, watch: "hüzünlü"),
        .init(id: "squalor", term: "squalor", context: "The family lived in squalor.", mode: .word, target: .english, watch: "sefalet, pislik"),
        .init(id: "wretchedness", term: "wretchedness", context: nil, mode: .word, target: .english, watch: "no context: general meaning only"),
        .init(id: "though", term: "though", context: "It was cold. I went out, though.", mode: .word, target: .english, watch: "yine de — sentence-final use"),
        // Other study languages.
        .init(id: "de-bekommen", term: "bekommen", context: "Ich habe gestern einen Brief bekommen.", mode: .word, target: .german, watch: "almak — false friend of 'become'; answer in German where asked"),
        .init(id: "es-embarazada", term: "embarazada", context: "Mi hermana está embarazada.", mode: .word, target: .spanish, watch: "hamile — not utanmış"),
        .init(id: "fr-librairie", term: "librairie", context: "J'ai acheté ce roman dans une petite librairie.", mode: .word, target: .french, watch: "kitapçı — not kütüphane"),
        // Sentences.
        .init(id: "s-raskolnikov", term: "Raskolnikov was not used to crowds, and, as we said before, he avoided society of every sort.", context: nil, mode: .sentence, target: .english, watch: "literary; 'society' = people, company"),
        .init(id: "s-had-i-known", term: "Had I known, I would have come earlier.", context: nil, mode: .sentence, target: .english, watch: "inversion = if I had known"),
        .init(id: "s-results", term: "The results, which were published last week, have been widely criticised.", context: nil, mode: .sentence, target: .english, watch: "non-defining clause"),
        .init(id: "s-no-sooner", term: "No sooner had he arrived than it started to rain.", context: nil, mode: .sentence, target: .english, watch: "no sooner … than = … gelir gelmez"),
        .init(id: "s-cats-dogs", term: "It's raining cats and dogs.", context: nil, mode: .sentence, target: .english, watch: "idiom: bardaktan boşanırcasına"),
    ]
}

/// One module's answer to one item, with its checks.
struct PromptEvalRecord: Codable {
    let item: String
    let module: String
    let term: String
    let context: String?
    let mode: String
    let target: String
    let watch: String
    let system: String
    let user: String
    let output: String
    let seconds: Double
    let maxTokens: Int
    let truncated: Bool
    let expectedLanguage: String?
    let detectedLanguage: String?
    let languageOK: Bool?
    let formatOK: Bool?
    let preamble: Bool
    let error: String?
}

struct PromptEvalRun: Codable {
    let date: Date
    let model: String
    let revision: Int
    let records: [PromptEvalRecord]
}

@MainActor
final class PromptEvaluationTests: XCTestCase {
    private var environment: [String: String] { ProcessInfo.processInfo.environment }

    func testRunTheEvaluationSet() async throws {
        try XCTSkipUnless(environment["RELL_PROMPT_EVAL"] == "1", "Prompt evaluation runs on request (RELL_PROMPT_EVAL=1)")
        let url = environment["RELL_EVAL_URL"] ?? "http://127.0.0.1:11434"
        let model = try XCTUnwrap(environment["RELL_EVAL_MODEL"], "RELL_EVAL_MODEL is required")
        let out = URL(fileURLWithPath: environment["RELL_EVAL_OUT"] ?? NSTemporaryDirectory() + "rell-prompt-eval.json")
        let limit = Int(environment["RELL_EVAL_LIMIT"] ?? "") ?? PromptEvalSet.items.count
        let capsModel = environment["RELL_EVAL_CAPS_MODEL"] ?? model

        var client = LLMClient()
        client.baseURLString = url
        client.model = model
        client.session = LLMClient.makeSession(timeout: 120)

        var records: [PromptEvalRecord] = []
        for item in PromptEvalSet.items.prefix(limit) {
            for module in ModuleType.allCases where module.isEnabled(mode: item.mode) {
                records.append(await Self.ask(module, item, client: client, capsModel: capsModel))
                // Partial results survive a stopped run.
                try Self.write(PromptEvalRun(date: Date(), model: model, revision: PromptTemplates.revision, records: records), to: out)
            }
        }
        print("PROMPT-EVAL wrote \(records.count) answers to \(out.path)")
    }

    private static func write(_ run: PromptEvalRun, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(run).write(to: url, options: .atomic)
    }

    private static func ask(_ module: ModuleType, _ item: PromptEvalItem, client: LLMClient, capsModel: String) async -> PromptEvalRecord {
        let native = PromptEvalSet.native
        let system = module.systemPrompt(customPreamble: "", nativeLanguage: native, targetLanguage: item.target)
        let user = module.userPrompt(term: item.term, mode: item.mode, detail: .short, domain: .general,
                                     context: item.context, nativeLanguage: native, targetLanguage: item.target,
                                     level: PromptEvalSet.level)
        let maxTokens = module.recommendedMaxTokens(mode: item.mode, detail: .short, modelIdentifier: capsModel)
        var started = Date()
        var output = ""
        var finish: LLMFinishReason?
        var failure: String?
        // A cloud model answers 502 now and then; such an answer says nothing
        // about the prompt, so try again, waiting a little longer each time.
        for attempt in 0..<4 {
            if attempt > 0 { try? await Task.sleep(for: .seconds(Double(attempt) * 5)) }
            started = Date()
            output = ""
            failure = nil
            do {
                finish = try await client.stream(system: system, user: user, temperature: module.recommendedTemperature,
                                                 maxTokens: maxTokens, topP: 0.9) { output += $0 }
                break
            } catch {
                failure = error.localizedDescription
            }
        }
        try? await Task.sleep(for: .milliseconds(300))
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let expected = expectedLanguage(module, native: native, target: item.target)
        let detected = detectedLanguage(text)
        return PromptEvalRecord(
            item: item.id, module: module.rawValue, term: item.term, context: item.context, mode: item.mode.rawValue,
            target: item.target.rawValue, watch: item.watch, system: system, user: user, output: text,
            seconds: Date().timeIntervalSince(started), maxTokens: maxTokens,
            truncated: InspectorViewModel.looksTruncated(finishReason: finish, outputLength: text.count, maxTokens: maxTokens),
            expectedLanguage: expected?.rawValue, detectedLanguage: detected?.rawValue,
            languageOK: expected.flatMap { expected in detected.map { $0 == expected } },
            formatOK: formatOK(module, text: text),
            preamble: hasPreamble(text), error: failure
        )
    }

    /// The language the module must answer in; nil where it mixes two or is
    /// a transcription.
    private static func expectedLanguage(_ module: ModuleType, native: Language, target: Language) -> Language? {
        switch module.outputLanguage(nativeLanguage: native, targetLanguage: target) {
        case .target(let language): return module == .pronunciationEN ? nil : language
        case .native(let language): return language
        case .mixed: return nil
        }
    }

    private static func detectedLanguage(_ text: String) -> Language? {
        guard text.count >= 20 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage.flatMap(LemmaMatcher.language(for:))
    }

    /// Whether the app's parsers read the answer: collocations as numbered
    /// entries with example and translation, usage notes with FREQ and REG.
    private static func formatOK(_ module: ModuleType, text: String) -> Bool? {
        switch module {
        case .collocations:
            let entries = ResultParser.parseCollocationEntries(text)
            return !entries.isEmpty && entries.allSatisfy { !$0.example.isEmpty && !$0.translationNative.isEmpty }
        case .usageNotesEN where !text.isEmpty && text.contains(":"):
            let labels = Set(ResultParser.parseUsageNoteRows(text).map(\.label))
            return labels.contains("FREQ") && labels.contains("REG")
        default:
            return nil
        }
    }

    private static func hasPreamble(_ text: String) -> Bool {
        let opening = text.prefix(40).lowercased()
        return ["sure", "here is", "here are", "of course", "certainly", "tabii", "işte", "elbette", "as a", "i'm "]
            .contains { opening.hasPrefix($0) }
    }
}
