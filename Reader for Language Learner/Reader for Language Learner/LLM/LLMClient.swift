//
//  LLMClient.swift
//  Reader for Language Learner
//
//  Created by Muhammet Korkmaz on 10.02.2026.
//

import Foundation

struct LLMClient {
    enum ClientError: LocalizedError {
        case invalidURL
        case serverNotReachable
        case unauthorized
        case badStatusCode(status: Int, body: String)
        case invalidResponse(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid LLM server URL."
            case .serverNotReachable:
                return "LLM server not reachable. Check that the server is running and the URL in Settings is correct."
            case .unauthorized:
                return "Authentication failed. Check your API key in Settings."
            case .badStatusCode(let status, let body):
                let truncated = body.count > 120 ? String(body.prefix(120)) + "…" : body
                if truncated.isEmpty {
                    return "LLM request failed (HTTP \(status))."
                }
                return "LLM request failed (HTTP \(status)): \(truncated)"
            case .invalidResponse(let details):
                return details
            }
        }
    }

    var baseURLString: String = LLMConfiguration.defaultServerURL
    var model: String = LLMConfiguration.defaultModel
    var apiKey: String?
    var session: URLSession = LLMClient.makeSession()

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
            stream: false
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

        let requestBody = ChatRequest(
            model: model,
            messages: [
                ChatMessage(role: "system", content: system),
                ChatMessage(role: "user", content: user)
            ],
            temperature: temperature,
            max_tokens: maxTokens,
            top_p: topP,
            stream: true
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

                await onToken(delta)
            }
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

// MARK: - Request / Response models

private struct ChatRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let max_tokens: Int
    let top_p: Double
    let stream: Bool
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
