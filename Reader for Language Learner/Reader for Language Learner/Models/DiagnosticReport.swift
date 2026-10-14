//
//  DiagnosticReport.swift
//  Reader for Language Learner
//
//  A plain-text report for "it's slow" or "it doesn't answer" (Roadmap v17
//  Sprint 3, approved decisions 4–5): versions, the Mac, Apple Intelligence,
//  the AI provider, the last speed test and the last requests' timings.
//  Shown in full before it's copied; nothing is sent. No words, sentences,
//  book titles or API keys — and a remote server's address is left out
//  (only its kind is named); a server on this Mac is written as is.
//

import Foundation

nonisolated enum DiagnosticReport {

    struct Facts: Sendable {
        var date: Date
        var appVersion: String
        var macOS: String
        var chip: String
        var memoryBytes: UInt64
        /// nil when Apple's model is ready; else why not.
        var appleUnavailableReason: String?
        var appleOnInRELL: Bool
        var providerType: String
        var model: String
        var onThisMac: Bool
        var serverURL: String
        var ollamaVersion: String?
        var timeout: Double
        var speedResults: [SpeedTest.Result]
        var requests: [LLMRequestRecord]
    }

    /// Requests listed, newest first.
    static let requestCount = 20

    static func text(_ facts: Facts) -> String {
        let memory = ByteCountFormatter.string(fromByteCount: Int64(facts.memoryBytes), countStyle: .memory)
        var lines: [String] = []
        lines.append(String(localized: "RELL diagnostic report · \(facts.date.formatted(date: .numeric, time: .shortened))"))
        lines.append("RELL \(facts.appVersion) · macOS \(facts.macOS) · \(facts.chip) · \(memory)")
        lines.append("")

        func field(_ label: String, _ value: String) {
            lines.append(label.padding(toLength: 20, withPad: " ", startingAt: 0) + " " + value)
        }
        field(String(localized: "Apple Intelligence"),
              facts.appleUnavailableReason.map { String(localized: "unavailable: \($0)") } ?? String(localized: "ready"))
        field(String(localized: "Apple model in RELL"), facts.appleOnInRELL ? String(localized: "on") : String(localized: "off"))
        var provider = "\(facts.providerType) · \(facts.model)"
        provider += facts.onThisMac ? String(localized: " (this Mac)") : String(localized: " (remote)")
        if let host = localAddress(facts.serverURL) { provider += " · \(host)" }
        field(String(localized: "Provider"), provider)
        if let version = facts.ollamaVersion { field(String(localized: "Ollama version"), version) }
        field(String(localized: "Timeout"), "\(Int(facts.timeout)) s")

        if !facts.speedResults.isEmpty {
            lines.append("")
            lines.append(String(localized: "Speed test"))
            for result in facts.speedResults {
                let name = result.isApple ? "Apple" : [result.engine, result.model].compactMap { $0 }.joined(separator: " · ")
                if let failure = result.failure {
                    lines.append("  \(name)   \(failure)")
                    continue
                }
                var parts: [String] = []
                if let load = result.load { parts.append(String(localized: "load \(seconds(load))")) }
                if let first = result.firstToken { parts.append(String(localized: "first word \(seconds(first))")) }
                if let speed = result.wordsPerSecond { parts.append(String(localized: "\(Int(speed.rounded())) words/s")) }
                lines.append("  \(name)   " + parts.joined(separator: " · "))
            }
        }

        let recent = facts.requests.suffix(requestCount).reversed()
        if !recent.isEmpty {
            lines.append("")
            lines.append(String(localized: "Recent requests (s)        wait  first  total  result"))
            for record in recent {
                let time = record.queuedAt.formatted(date: .omitted, time: .standard)
                let what = String(record.origin.rawValue + (record.detail.map { "/\($0)" } ?? "")).padding(toLength: 22, withPad: " ", startingAt: 0)
                let engine = (record.engine == AppleOnDevice.providerLabel ? "Apple" : record.engine).padding(toLength: 10, withPad: " ", startingAt: 0)
                lines.append("  \(time) \(what) \(engine) \(number(record.wait)) \(number(record.firstToken)) \(number(record.total))  \(outcome(record))")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// The server's host and port when it's on this Mac; nil for a remote
    /// one, whose address stays out of the report.
    static func localAddress(_ serverURL: String) -> String? {
        guard let url = URL(string: serverURL), let host = url.host?.lowercased(),
              ["127.0.0.1", "localhost", "::1", "[::1]"].contains(host) else { return nil }
        return url.port.map { "\(host):\($0)" } ?? host
    }

    private static func seconds(_ value: TimeInterval) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1)))) s"
    }

    private static func number(_ value: TimeInterval?) -> String {
        let text = value.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—"
        return String(repeating: " ", count: max(0, 5 - text.count)) + text
    }

    private static func outcome(_ record: LLMRequestRecord) -> String {
        switch record.outcome {
        case .finished:          return "done"
        case .cancelled:         return record.startedAt == nil ? "not sent" : "stopped"
        case .failed(let kind):  return "failed (\(kind))"
        case nil:                return record.startedAt == nil ? "waiting" : "running"
        }
    }
}

// MARK: - Gathering

extension DiagnosticReport {
    /// The facts as they are now. Asks a local Ollama for its version.
    @MainActor
    static func gather(now: Date = Date()) async -> Facts {
        let configuration = LLMConfiguration()
        var ollamaVersion: String?
        if configuration.providerType == .ollama, localAddress(configuration.serverURL) != nil,
           let url = URL(string: "\(configuration.serverURL)/api/version"),
           let (data, _) = try? await LLMSessionPool.session(timeout: 5).data(from: url),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            ollamaVersion = object["version"] as? String
        }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return Facts(
            date: now,
            appVersion: WhatsNew.appVersion,
            macOS: "\(os.majorVersion).\(os.minorVersion)" + (os.patchVersion > 0 ? ".\(os.patchVersion)" : ""),
            chip: chipName(),
            memoryBytes: ProcessInfo.processInfo.physicalMemory,
            appleUnavailableReason: AppleOnDevice.unavailableReason,
            appleOnInRELL: AppleOnDevice.isEnabled,
            providerType: configuration.providerType.rawValue,
            model: configuration.model,
            onThisMac: configuration.runsOnThisMac,
            serverURL: configuration.serverURL,
            ollamaVersion: ollamaVersion,
            timeout: configuration.timeout,
            speedResults: SpeedTest.shared.results,
            requests: LLMRequestLog.shared.records
        )
    }

    /// "Apple M4".
    static func chipName() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return "Mac" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }
}
