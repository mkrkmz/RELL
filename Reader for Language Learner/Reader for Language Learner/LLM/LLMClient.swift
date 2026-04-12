//
//  LLMClient.swift
//  Reader for Language Learner
//
//  Created by Muhammet Korkmaz on 10.02.2026.
//

import Foundation
import os

struct LLMClient {
    nonisolated static let streamFlushInterval: Duration = .milliseconds(80)
    nonisolated static let preferredFlushCharacterCount = 50
    nonisolated static let streamGapWarningThreshold: TimeInterval = 1.5
    nonisolated static let logger = Logger(subsystem: "com.rell.app", category: "llm")

    enum ClientError: LocalizedError {
        case invalidURL
        case serverNotReachable
        case unauthorized
        case badStatusCode(status: Int, body: String)
        case invalidResponse(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "The server URL in Settings is invalid. Check for typos and make sure it starts with http://."
            case .serverNotReachable:
                return "Cannot reach the AI server. Make sure LM Studio (or your chosen provider) is running, then try again."
            case .unauthorized:
                return "Authentication failed. Check that your API key in Settings is correct and hasn't expired."
            case .badStatusCode(let status, let body):
                switch status {
                case 400:
                    return "The request was rejected by the server (400). The model may not support the selected parameters."
                case 404:
                    return "Model not found (404). Check the model name in Settings — it may be misspelled or not loaded."
                case 429:
                    return "Too many requests (429). You've hit a rate limit. Wait a moment and try again."
                case 500...599:
                    return "The AI server encountered an error (\(status)). Try restarting the server or switching to a different model."
                default:
                    let hint = body.count > 80 ? String(body.prefix(80)) + "…" : body
                    return hint.isEmpty
                        ? "Unexpected server response (HTTP \(status))."
                        : "Server error (\(status)): \(hint)"
                }
            case .invalidResponse(let details):
                return details
            }
        }
    }

    var baseURLString: String = LLMConfiguration.defaultServerURL
    var model: String = LLMConfiguration.defaultModel
    var apiKey: String?
    var session: URLSession = LLMClient.makeSession()

    private var reasoningEffort: String? {
        guard shouldDisableReasoning else { return nil }
        return "none"
    }

    private var shouldDisableReasoning: Bool {
        isLMStudioLocalServer
    }

    private var isLMStudioLocalServer: Bool {
        guard let url = URL(string: baseURLString),
              let host = url.host?.lowercased() else { return false }
        let isLocalHost = host == "127.0.0.1" || host == "localhost"
        return isLocalHost && url.port == 1234
    }

    /// URLSession configured with the given request timeout.
    static func makeSession(timeout: Double = LLMConfiguration.defaultTimeout) -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = timeout
        config.timeoutIntervalForResource = max(300, timeout * 5)
        return URLSession(configuration: config)
    }

    // MARK: - Non-streaming (kept for any call sites not yet migrated)

    func chat(
        system: String,
        user: String,
        temperature: Double = 0.2,
        maxTokens: Int = 512,
        topP: Double = 0.9
    ) async throws -> String {
        guard let url = URL(string: "\(baseURLString)/v1/chat/completions") else {
            throw ClientError.invalidURL
        }

        let requestBody = ChatRequest(
            model: model,
            messages: [
                ChatMessage(role: "system", content: system),
                ChatMessage(role: "user", content: user)
            ],
            temperature: temperature,
            max_tokens: maxTokens,
            top_p: topP,
            stream: false,
            reasoning_effort: reasoningEffort
        )
        let bodyData = try JSONEncoder().encode(requestBody)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = bodyData

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ClientError.invalidResponse("Received an unexpected response from the LLM server.")
            }

            if httpResponse.statusCode == 401 {
                throw ClientError.unauthorized
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let responseBody = String(data: data, encoding: .utf8) ?? "<non-utf8 response>"
                throw ClientError.badStatusCode(
                    status: httpResponse.statusCode,
                    body: responseBody
                )
            }

            let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
            guard let content = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines),
                  !content.isEmpty else {
                throw ClientError.invalidResponse("LLM server returned an empty answer.")
            }
            return content
        } catch let urlError as URLError {
            switch urlError.code {
            case .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet, .timedOut:
                throw ClientError.serverNotReachable
            default:
                throw urlError
            }
        } catch is DecodingError {
            throw ClientError.invalidResponse("Could not parse LLM server response format.")
        }
    }

    // MARK: - Streaming (SSE)

    /// Streams tokens from LM Studio's Server-Sent Events endpoint.
    /// `onToken` is called on each delta content chunk as it arrives.
    /// The caller's `Task` can be cancelled to abort mid-stream.
    func stream(
        system: String,
        user: String,
        temperature: Double = 0.2,
        maxTokens: Int = 512,
        topP: Double = 0.9,
        onToken: @MainActor @escaping (String) -> Void
    ) async throws {
        guard let url = URL(string: "\(baseURLString)/v1/chat/completions") else {
            throw ClientError.invalidURL
        }

        LLMClient.logger.info(
            "Starting stream model=\(self.model, privacy: .public) url=\(self.baseURLString, privacy: .public) reasoning_effort=\(self.reasoningEffort ?? "default", privacy: .public) max_tokens=\(maxTokens)"
        )

        let requestBody = ChatRequest(
            model: model,
            messages: [
                ChatMessage(role: "system", content: system),
                ChatMessage(role: "user", content: user)
            ],
            temperature: temperature,
            max_tokens: maxTokens,
            top_p: topP,
            stream: true,
            reasoning_effort: reasoningEffort
        )
        let bodyData = try JSONEncoder().encode(requestBody)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = bodyData

        do {
            let (asyncBytes, response) = try await session.bytes(for: request)
            let flushState = StreamFlushState()
            let diagnostics = StreamDiagnostics()

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ClientError.invalidResponse("Received an unexpected response from the LLM server.")
            }
            if httpResponse.statusCode == 401 {
                throw ClientError.unauthorized
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                throw ClientError.badStatusCode(status: httpResponse.statusCode, body: "")
            }

            // Read SSE lines: each non-empty line starting with "data: "
            for try await line in asyncBytes.lines {
                // Respect task cancellation
                try Task.checkCancellation()

                guard line.hasPrefix("data: ") else { continue }
                let payload = String(line.dropFirst(6))
                if payload == "[DONE]" { break }

                guard let data = payload.data(using: .utf8),
                      let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
                      let delta = chunk.choices.first?.delta.content,
                      !delta.isEmpty
                else { continue }

                await diagnostics.recordChunk(delta)
                await flushState.append(delta, deliver: onToken)
            }

            await flushState.flush(force: true, deliver: onToken)
            await diagnostics.finish()
        } catch let urlError as URLError {
            switch urlError.code {
            case .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
                 .notConnectedToInternet, .timedOut:
                throw ClientError.serverNotReachable
            default:
                throw urlError
            }
        } catch is CancellationError {
            // Swallow — caller handles via task state
            return
        } catch is DecodingError {
            throw ClientError.invalidResponse("Could not parse LLM server stream.")
        }
    }
}

private actor StreamFlushState {
    private var buffer = ""
    private var lastFlush = ContinuousClock.now

    func append(
        _ delta: String,
        deliver: @MainActor @escaping (String) -> Void
    ) async {
        buffer += delta

        let elapsed = ContinuousClock.now - lastFlush
        let timerExpired = elapsed >= LLMClient.streamFlushInterval
        let bufferFull = buffer.count >= LLMClient.preferredFlushCharacterCount

        // Flush on boundary chars only when the minimum interval has passed,
        // preventing micro-flushes that choke SwiftUI with re-renders.
        let boundaryReady = timerExpired && (
            buffer.last?.isWhitespace == true ||
            buffer.last.map(isBoundaryCharacter(_:)) == true
        )

        if bufferFull || boundaryReady {
            await flush(force: false, deliver: deliver)
        }
    }

    func flush(
        force: Bool,
        deliver: @MainActor @escaping (String) -> Void
    ) async {
        guard force || !buffer.isEmpty else { return }
        guard !buffer.isEmpty else { return }

        let chunk = buffer
        buffer.removeAll(keepingCapacity: true)
        lastFlush = ContinuousClock.now
        await deliver(chunk)
    }

    private func isBoundaryCharacter(_ character: Character) -> Bool {
        switch character {
        case ".", ",", "!", "?", ":", ";", "\n":
            return true
        default:
            return false
        }
    }
}

private actor StreamDiagnostics {
    private let start = Date()
    private var lastChunkAt: Date?
    private var chunkCount = 0
    private var characterCount = 0

    func recordChunk(_ delta: String) {
        let now = Date()
        chunkCount += 1
        characterCount += delta.count

        if let lastChunkAt {
            let gap = now.timeIntervalSince(lastChunkAt)
            if gap >= LLMClient.streamGapWarningThreshold {
                LLMClient.logger.warning(
                    "Stream gap detected: \(String(format: "%.2f", gap), privacy: .public)s after chunk \(self.chunkCount - 1)"
                )
            }
        } else {
            let firstChunkLatency = now.timeIntervalSince(start)
            LLMClient.logger.info(
                "First stream chunk after \(String(format: "%.2f", firstChunkLatency), privacy: .public)s"
            )
        }

        lastChunkAt = now
    }

    func finish() {
        let total = Date().timeIntervalSince(start)
        LLMClient.logger.info(
            "Stream finished in \(String(format: "%.2f", total), privacy: .public)s chunks=\(self.chunkCount) chars=\(self.characterCount)"
        )
    }
}

// MARK: - Request / Response models

private struct ChatRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let max_tokens: Int
    let top_p: Double
    let stream: Bool
    let reasoning_effort: String?
}

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct ChatResponse: Codable {
    let choices: [ChatChoice]
}

private struct ChatChoice: Codable {
    let message: ChatMessage
}

// SSE streaming models
private struct StreamChunk: Codable {
    let choices: [StreamChoice]
}

private struct StreamChoice: Codable {
    let delta: StreamDelta
}

private struct StreamDelta: Codable {
    let content: String?
}
