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
    var model: String = "claude-sonnet-4-20250514"
    var apiKey: String = ""
    var session: URLSession = AnthropicClient.makeSession()

    static func makeSession(timeout: Double = LLMConfiguration.defaultTimeout) -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = timeout
        config.timeoutIntervalForResource = max(300, timeout * 5)
        return URLSession(configuration: config)
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

    func stream(
        system: String,
        user: String,
        temperature: Double = 0.2,
        maxTokens: Int = 512,
        topP: Double = 0.9,
        onToken: @MainActor @escaping (String) -> Void
    ) async throws {
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
                throw ClientError.badStatusCode(status: httpResponse.statusCode, body: "")
            }

            // Anthropic SSE format:
            // event: content_block_delta
            // data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"..."}}
            //
            // event: message_stop
            for try await line in asyncBytes.lines {
                try Task.checkCancellation()

                guard line.hasPrefix("data: ") else { continue }
                let payload = String(line.dropFirst(6))

                guard let data = payload.data(using: .utf8),
                      let event = try? JSONDecoder().decode(StreamEvent.self, from: data)
                else { continue }

                switch event.type {
                case "content_block_delta":
                    if let text = event.delta?.text, !text.isEmpty {
                        await onToken(text)
                    }
                case "message_stop":
                    return
                default:
                    continue
                }
            }
        } catch let urlError as URLError {
            switch urlError.code {
            case .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet, .timedOut:
                throw ClientError.serverNotReachable
            default:
                throw urlError
            }
        } catch is CancellationError {
            return
        } catch is DecodingError {
            throw ClientError.invalidResponse("Could not parse Anthropic stream.")
        }
    }

    // MARK: - Request builder

    private func buildRequest(
        system: String, user: String,
        temperature: Double, maxTokens: Int, topP: Double,
        stream: Bool
    ) throws -> URLRequest {
        guard let url = URL(string: "\(baseURLString)/v1/messages") else {
            throw ClientError.invalidURL
        }

        let body = MessagesRequest(
            model: model,
            max_tokens: maxTokens,
            system: system,
            messages: [AnthropicMessage(role: "user", content: user)],
            temperature: temperature,
            top_p: topP,
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
    let temperature: Double
    let top_p: Double
    let stream: Bool
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
}
