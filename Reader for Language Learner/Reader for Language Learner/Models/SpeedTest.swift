//
//  SpeedTest.swift
//  Reader for Language Learner
//
//  Settings ▸ AI ▸ Speed (Roadmap v17 Sprint 2, approved decision 4): one
//  short request to each engine, twice, one after another — only when you
//  press the button. The first request shows whether the model had to load;
//  the second how fast it answers once loaded. The advice turns the numbers
//  into what to do. The test waits behind anything you ask for meanwhile
//  (background priority) and sends a fixed sentence, nothing of yours.
//

import Foundation

@MainActor
@Observable
final class SpeedTest {
    /// Off the main actor: on macOS 15 a main-actor deinit run outside a
    /// task crashes when it releases another one (v16 S0, CI crash reports).
    nonisolated deinit {}

    /// One for the app: Settings shows it, the diagnostic report reads it.
    static let shared = SpeedTest()

    nonisolated struct Result: Identifiable, Equatable, Sendable {
        var id: String { engine + (model ?? "") }
        let engine: String
        let model: String?
        let isApple: Bool
        let onThisMac: Bool
        /// How long loading the model took; nil when it was already loaded
        /// (or the engine doesn't load one).
        let load: TimeInterval?
        /// First word, model loaded.
        let firstToken: TimeInterval?
        let wordsPerSecond: Double?
        /// Size of the loaded model, when the server says (Ollama).
        let modelBytes: Int64?
        let failure: String?
    }

    enum State: Equatable {
        case idle
        case running(engine: String)
        case done
    }

    private(set) var state: State = .idle
    private(set) var results: [Result] = []

    static let system = "You are a helpful assistant. Answer in plain English."
    static let prompt = "Write three short sentences about reading a novel in a foreign language."
    static let maxTokens = 80

    func run() async {
        guard !isRunning else { return }
        results = []
        let configuration = LLMConfiguration()
        var engines: [(provider: any LLMProvider, route: LLMRoute)] = []
        if AppleOnDevice.currentRoute(for: nil) == .appleOnDevice {
            engines.append((AppleOnDevice.provider(for: nil), .appleOnDevice))
        }
        engines.append((configuration.makeProvider(), .configured))

        for (provider, route) in engines {
            let name = route == .appleOnDevice ? AppleOnDevice.providerLabel : configuration.providerType.rawValue
            state = .running(engine: name)
            results.append(await measure(provider, route: route, configuration: configuration))
        }
        state = .done
    }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    private func measure(_ provider: any LLMProvider, route: LLMRoute, configuration: LLMConfiguration) async -> Result {
        let log = LLMRequestLog.shared
        let isApple = route == .appleOnDevice
        let onThisMac = !isApple && configuration.runsOnThisMac
        var records: [LLMRequestRecord] = []
        var lastAnswer = ""
        for _ in 0..<2 {
            let recorded = log.recording(provider, origin: .speedTest, route: route)
            var answer = ""
            do {
                try await recorded.stream(system: Self.system, user: Self.prompt, temperature: 0,
                                          maxTokens: Self.maxTokens, topP: 1) { answer += $0 }
            } catch {
                let message = LLMErrorMessage.userMessage(for: error)
                return Result(engine: isApple ? AppleOnDevice.providerLabel : configuration.providerType.rawValue,
                              model: isApple ? nil : configuration.model, isApple: isApple, onThisMac: onThisMac,
                              load: nil, firstToken: nil, wordsPerSecond: nil, modelBytes: nil, failure: message)
            }
            if let record = log.record(recorded.id) { records.append(record) }
            lastAnswer = answer
        }
        let cold = records.first?.firstToken
        let warm = records.last?.firstToken
        var bytes: Int64?
        if onThisMac, configuration.providerType == .ollama {
            bytes = await Self.ollamaModelBytes(serverURL: configuration.serverURL, model: configuration.model)
        }
        return Result(
            engine: isApple ? AppleOnDevice.providerLabel : configuration.providerType.rawValue,
            model: isApple ? nil : configuration.model,
            isApple: isApple, onThisMac: onThisMac,
            load: onThisMac ? Self.loadTime(cold: cold, warm: warm) : nil,
            firstToken: warm,
            wordsPerSecond: records.last.flatMap { Self.wordsPerSecond(answer: lastAnswer, record: $0) },
            modelBytes: bytes,
            failure: nil
        )
    }

    // MARK: Pure

    /// The extra the first request took over the second, when it's clearly
    /// a load rather than noise.
    nonisolated static func loadTime(cold: TimeInterval?, warm: TimeInterval?) -> TimeInterval? {
        guard let cold, let warm else { return nil }
        let extra = cold - warm
        return extra >= 2 ? extra : nil
    }

    nonisolated static func wordsPerSecond(answer: String, record: LLMRequestRecord) -> Double? {
        guard let first = record.firstTokenAt, let end = record.finishedAt else { return nil }
        let seconds = end.timeIntervalSince(first)
        let words = answer.split(whereSeparator: \.isWhitespace).count
        guard seconds >= 0.05, words >= 3 else { return nil }
        return Double(words) / seconds
    }

    /// The loaded model's size from Ollama's `/api/ps`.
    nonisolated static func ollamaModelBytes(fromPS data: Data, model: String) -> Int64? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = object["models"] as? [[String: Any]] else { return nil }
        let entry = models.first { ($0["name"] as? String) == model || ($0["model"] as? String) == model }
        return (entry?["size"] as? NSNumber)?.int64Value
    }

    private static func ollamaModelBytes(serverURL: String, model: String) async -> Int64? {
        guard let url = URL(string: "\(serverURL)/api/ps"),
              let (data, _) = try? await LLMSessionPool.session(timeout: 10).data(from: url) else { return nil }
        return ollamaModelBytes(fromPS: data, model: model)
    }
}

// MARK: - Advice

/// What to do about the numbers (approved mockup, "Öneriler"). Pure.
nonisolated enum SpeedAdvice {
    enum AppleState: Equatable, Sendable {
        case on
        case offInRELL
        case unavailable(reason: String)
    }

    struct Item: Equatable, Identifiable, Sendable {
        enum Kind: Equatable, Sendable { case good, info, warning }
        var id: String { title }
        let kind: Kind
        let title: String
        let detail: String
    }

    /// Words a second below which a local model feels slow.
    static let slowWordsPerSecond = 12.0

    /// The model size this Mac runs well (first-run flow, v17 S3).
    static func modelSizeHint(memoryBytes: UInt64) -> String {
        let gigabytes = Int((Double(memoryBytes) / 1_073_741_824).rounded())
        let size: String
        switch gigabytes {
        case ..<12:  size = "1–4B"
        case ..<24:  size = "4–8B"
        case ..<48:  size = "8–14B"
        default:     size = "14–32B"
        }
        return String(localized: "This Mac has \(gigabytes) GB of memory: a \(size) model (Q4) runs fast here. Bigger ones answer slowly; cloud models (…-cloud) don't use this Mac at all.")
    }

    static func items(apple: AppleState, results: [SpeedTest.Result], physicalMemory: UInt64) -> [Item] {
        var items: [Item] = []
        let benefit = String(localized: "With it, definitions, meanings, examples, synonyms and usage notes — and the chapter warm-up, recap and glosses — answer in about a second, and your AI provider is left free for the rest.")
        switch apple {
        case .on:
            break
        case .offInRELL:
            items.append(Item(kind: .warning, title: String(localized: "Turn on Apple's on-device model"), detail: benefit))
        case .unavailable(let reason):
            items.append(Item(kind: .warning, title: String(localized: "Apple's on-device model isn't available"),
                              detail: "\(reason) \(benefit)"))
        }

        for result in results where !result.isApple {
            let name = [result.engine, result.model].compactMap { $0 }.joined(separator: " · ")
            if let failure = result.failure {
                items.append(Item(kind: .warning, title: String(localized: "\(name) didn't answer"), detail: failure))
                continue
            }
            if result.onThisMac {
                if let speed = result.wordsPerSecond, speed < slowWordsPerSecond {
                    var detail = String(localized: "It writes about \(Int(speed.rounded())) words a second. A smaller model (4–8B) answers faster.")
                    if let bytes = result.modelBytes, physicalMemory > 0 {
                        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
                        let memory = ByteCountFormatter.string(fromByteCount: Int64(physicalMemory), countStyle: .memory)
                        detail = String(localized: "It takes \(size) of this Mac's \(memory) and writes about \(Int(speed.rounded())) words a second. A smaller model (4–8B) answers faster.")
                    }
                    items.append(Item(kind: .warning, title: String(localized: "The model is slow on this Mac"), detail: detail))
                }
                if let load = result.load {
                    items.append(Item(kind: .info, title: String(localized: "The first request loaded the model"),
                                      detail: String(localized: "Loading took \(AnswerFooter.seconds(load)). RELL now loads the model when you open a book and asks the server to keep it.")))
                }
            } else if let first = result.firstToken, first > AnswerFooter.slowCloudThreshold {
                items.append(Item(kind: .warning, title: String(localized: "The cloud model was slow to answer"),
                                  detail: String(localized: "The first word took \(AnswerFooter.seconds(first)). This usually comes from the provider — your account's limits or its load — or from the network. With Ollama, updating Ollama can help.")))
            }
        }

        if !items.contains(where: { $0.kind == .warning }) {
            items.insert(Item(kind: .good, title: String(localized: "All good"),
                              detail: String(localized: "Answers start in about a second.")), at: 0)
        }
        return items
    }
}
