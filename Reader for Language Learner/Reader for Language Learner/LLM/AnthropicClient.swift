//
//  AnthropicClient.swift
//  Reader for Language Learner
//
//  Anthropic Claude Messages API client.
//  Uses /v1/messages endpoint with x-api-key authentication.
//

import Foundation

struct AnthropicClient: LLMProvider {

    enum ClientError: LocalizedError {
        case invalidURL
        case serverNotReachable
        case unauthorized
        case badStatusCode(status: Int, body: String)
        case invalidResponse(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid Anthropic API URL."
            case .serverNotReachable:
                return "Anthropic API not reachable. Check your internet connection."
            case .unauthorized:
                return "Authentication failed. Check your Anthropic API key in Settings."
            case .badStatusCode(let status, let body):
                let truncated = body.count > 120 ? String(body.prefix(120)) + "…" : body
                if truncated.isEmpty {
                    return "Anthropic request failed (HTTP \(status))."
                }
                return "Anthropic request failed (HTTP \(status)): \(truncated)"
            case .invalidResponse(let details):
                return details
            }
        }
    }

    var baseURLString: String = "https://api.anthropic.com"
    var model: String = AnthropicModelTraits.defaultModel
    var apiKey: String = ""
    var session: URLSession = AnthropicClient.makeSession()

    static func makeSession(timeout: Double = LLMConfiguration.defaultTimeout) -> URLSession {
        LLMSessionPool.session(timeout: timeout)
    }

    // MARK: - Non-streaming

    func chat(
        system: String,
        user: String,
        temperature: Double = 0.2,
        maxTokens: Int = 512,
        topP: Double = 0.9
    ) async throws -> String {
        let request = try buildRequest(
            system: system, user: user,
            temperature: temperature, maxTokens: maxTokens, topP: topP,
            stream: false
        )

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ClientError.invalidResponse("Received an unexpected response from Anthropic API.")
            }

            if httpResponse.statusCode == 401 {
                throw ClientError.unauthorized
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let responseBody = String(data: data, encoding: .utf8) ?? "<non-utf8 response>"
                throw ClientError.badStatusCode(status: httpResponse.statusCode, body: responseBody)
            }

            let decoded = try JSONDecoder().decode(MessagesResponse.self, from: data)
            let text = decoded.content
                .compactMap { block -> String? in
                    if case .text(let t) = block { return t }
                    return nil
                }
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !text.isEmpty else {
                throw ClientError.invalidResponse("Anthropic returned an empty answer.")
            }
            return text
        } catch let urlError as URLError {
            switch urlError.code {
            case .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet, .timedOut:
                throw ClientError.serverNotReachable
            default:
                throw urlError
            }
        } catch is DecodingError {
            throw ClientError.invalidResponse("Could not parse Anthropic response format.")
        }
    }

    // MARK: - Streaming (SSE)

    @discardableResult
    func stream(
        system: String,
        user: String,
        temperature: Double = 0.2,
        maxTokens: Int = 512,
        topP: Double = 0.9,
        onToken: @MainActor @escaping (String) -> Void
    ) async throws -> LLMFinishReason? {
        let request = try buildRequest(
            system: system, user: user,
            temperature: temperature, maxTokens: maxTokens, topP: topP,
            stream: true
        )

        do {
            let (asyncBytes, response) = try await session.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ClientError.invalidResponse("Received an unexpected response from Anthropic API.")
            }
            if httpResponse.statusCode == 401 {
                throw ClientError.unauthorized
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                let body = await LLMSessionPool.errorBody(from: asyncBytes)
                throw ClientError.badStatusCode(status: httpResponse.statusCode, body: body)
            }

            // Anthropic SSE format:
            // event: content_block_delta
            // data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"..."}}
            //
            // event: message_delta  (carries stop_reason)
            // event: message_stop
            var finishReason: LLMFinishReason?

            for try await line in asyncBytes.lines {
                try Task.checkCancellation()

                guard let payload = LLMSessionPool.ssePayload(line) else { continue }

                guard let data = payload.data(using: .utf8),
                      let event = try? JSONDecoder().decode(StreamEvent.self, from: data)
                else { continue }

                switch event.type {
                case "content_block_delta":
                    if let text = event.delta?.text, !text.isEmpty {
                        await onToken(text)
                    }
                case "message_delta":
                    if let rawReason = event.delta?.stop_reason {
                        finishReason = LLMFinishReason(anthropicRawValue: rawReason)
                    }
                case "message_stop":
                    return finishReason
                default:
                    continue
                }
            }
            return finishReason
        } catch let urlError as URLError {
            switch urlError.code {
            case .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet, .timedOut:
                throw ClientError.serverNotReachable
            default:
                throw urlError
            }
        } catch is CancellationError {
            return nil
        } catch is DecodingError {
            throw ClientError.invalidResponse("Could not parse Anthropic stream.")
        }
    }

    // MARK: - Request builder

    func buildRequest(
        system: String, user: String,
        temperature: Double, maxTokens: Int, topP: Double,
        stream: Bool
    ) throws -> URLRequest {
        guard let url = URL(string: "\(baseURLString)/v1/messages") else {
            throw ClientError.invalidURL
        }

        // Sampling and thinking depend on the model — see AnthropicModelTraits.
        // `topP` is accepted for LLMProvider conformance but never sent.
        let sampling = AnthropicModelTraits.acceptsSampling(model)
        let thinks = AnthropicModelTraits.thinksByDefault(model)
        let body = MessagesRequest(
            model: model,
            max_tokens: thinks ? maxTokens + AnthropicModelTraits.thinkingHeadroom : maxTokens,
            system: system,
            messages: [AnthropicMessage(role: "user", content: user)],
            temperature: sampling ? temperature : nil,
            output_config: sampling ? nil : OutputConfig(effort: "low"),
            stream: stream
        )
        let bodyData = try JSONEncoder().encode(body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = bodyData
        return request
    }
}

// MARK: - Request / Response models

private struct MessagesRequest: Codable {
    let model: String
    let max_tokens: Int
    let system: String
    let messages: [AnthropicMessage]
    let temperature: Double?
    let output_config: OutputConfig?
    let stream: Bool
}

private struct OutputConfig: Codable {
    let effort: String
}

private struct AnthropicMessage: Codable {
    let role: String
    let content: String
}

private struct MessagesResponse: Codable {
    let content: [ContentBlock]
}

private enum ContentBlock: Codable {
    case text(String)
    case other

    private enum CodingKeys: String, CodingKey {
        case type, text
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        if type == "text", let text = try container.decodeIfPresent(String.self, forKey: .text) {
            self = .text(text)
        } else {
            self = .other
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .other:
            try container.encode("other", forKey: .type)
        }
    }
}

// MARK: - Stream event models

private struct StreamEvent: Codable {
    let type: String
    let delta: StreamDelta?
}

private struct StreamDelta: Codable {
    let type: String?
    let text: String?
    let stop_reason: String?
}

// MARK: - Model traits

/// What a Claude model accepts, from its id. The request used to send both
/// `temperature` and `top_p` to every model: Claude 4.x rejects the pair,
/// and Opus 4.7+, Sonnet 5, Opus 5 and later reject sampling parameters
/// altogether (HTTP 400 on every request).
enum AnthropicModelTraits {
    static let defaultModel = "claude-opus-5"

    /// Extra `max_tokens` for models that think by default. Thinking tokens
    /// count against `max_tokens`, and RELL's per-module budgets (100–900)
    /// were sized for the visible answer alone.
    static let thinkingHeadroom = 2_048

    /// Older models that still take `temperature`. An allow-list on purpose:
    /// a model RELL has never heard of is newer, and newer models reject it.
    private static let samplingPrefixes = [
        "claude-3",
        "claude-haiku-4-5",
        "claude-sonnet-4-0", "claude-sonnet-4-2025", "claude-sonnet-4-5", "claude-sonnet-4-6",
        "claude-opus-4-0", "claude-opus-4-2025", "claude-opus-4-1", "claude-opus-4-5", "claude-opus-4-6",
    ]

    /// Opus 4.7/4.8 reject sampling but run without thinking unless asked.
    private static let noDefaultThinkingPrefixes = ["claude-opus-4-7", "claude-opus-4-8"]

    nonisolated static func acceptsSampling(_ model: String) -> Bool {
        let id = model.lowercased()
        return samplingPrefixes.contains { id.hasPrefix($0) }
    }

    /// Models that think adaptively unless told otherwise (Sonnet 5, Opus 5
    /// and later). They get `effort: low` — a word lookup doesn't need deep
    /// reasoning — plus `thinkingHeadroom` so any thinking can't eat the answer.
    nonisolated static func thinksByDefault(_ model: String) -> Bool {
        let id = model.lowercased()
        return !acceptsSampling(id) && !noDefaultThinkingPrefixes.contains { id.hasPrefix($0) }
    }
}
