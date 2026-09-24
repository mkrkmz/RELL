//
//  LLMTransportTests.swift
//  Reader for Language LearnerTests
//
//  v1.39: retries never duplicate a streamed answer, a permanent 4xx isn't
//  retried, a failed module isn't cached, SSE parsing tolerates `data:`
//  without a space, and Anthropic requests only carry parameters the model
//  accepts.
//

import XCTest
@testable import Reader_for_Language_Learner

// MARK: - Fakes

@MainActor
private final class ScriptedProvider: LLMProvider {
    /// One entry per call: tokens to emit, then an optional error.
    var script: [(tokens: [String], error: Error?)]
    private(set) var calls = 0

    init(_ script: [(tokens: [String], error: Error?)]) {
        self.script = script
    }

    func chat(system: String, user: String, temperature: Double, maxTokens: Int, topP: Double) async throws -> String {
        ""
    }

    func stream(
        system: String, user: String, temperature: Double, maxTokens: Int, topP: Double,
        onToken: @MainActor @escaping (String) -> Void
    ) async throws -> LLMFinishReason? {
        let step = script[min(calls, script.count - 1)]
        calls += 1
        for token in step.tokens { onToken(token) }
        if let error = step.error { throw error }
        return .stop
    }
}

/// Serves one canned HTTP response to whatever the session asks for.
private final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
final class LLMTransportTests: XCTestCase {
    private static var retained: [AnyObject] = []

    private func resilient(_ inner: any LLMProvider) -> ResilientLLMProvider {
        let breaker = CircuitBreaker()
        Self.retained.append(breaker)
        return ResilientLLMProvider(provider: inner, circuitBreaker: breaker, maxRetries: 2, baseDelay: 0.001)
    }

    private func collect(_ provider: any LLMProvider) async throws -> String {
        var output = ""
        _ = try await provider.stream(system: "", user: "", temperature: 0.1, maxTokens: 50, topP: 0.9) { output += $0 }
        return output
    }

    // MARK: Retry

    /// Reproduced in the v12 review: "Hello worldHello world".
    func testStreamThatFailsMidAnswerIsNotRetried() async throws {
        let inner = ScriptedProvider([
            (["Hello ", "world"], LLMClient.ClientError.serverNotReachable),
            (["Hello ", "world"], nil),
        ])
        var output = ""
        do {
            _ = try await resilient(inner).stream(system: "", user: "", temperature: 0.1, maxTokens: 50, topP: 0.9) {
                output += $0
            }
            XCTFail("the mid-stream failure should surface")
        } catch {}
        XCTAssertEqual(output, "Hello world")
        XCTAssertEqual(inner.calls, 1)
    }

    func testStreamThatFailsBeforeAnyTokenIsRetried() async throws {
        let inner = ScriptedProvider([
            ([], LLMClient.ClientError.serverNotReachable),
            (["Hello ", "world"], nil),
        ])
        let output = try await collect(resilient(inner))
        XCTAssertEqual(output, "Hello world")
        XCTAssertEqual(inner.calls, 2)
    }

    func testPermanentClientErrorIsNotRetried() async throws {
        let inner = ScriptedProvider([([], LLMClient.ClientError.badStatusCode(status: 404, body: "model not found"))])
        do {
            _ = try await collect(resilient(inner))
            XCTFail("a 404 should surface")
        } catch {}
        XCTAssertEqual(inner.calls, 1)
    }

    func testRateLimitIsRetried() async throws {
        let inner = ScriptedProvider([
            ([], AnthropicClient.ClientError.badStatusCode(status: 429, body: "")),
            (["ok"], nil),
        ])
        let output = try await collect(resilient(inner))
        XCTAssertEqual(output, "ok")
        XCTAssertEqual(inner.calls, 2)
    }

    func testPermanentStatusClassification() async {
        XCTAssertTrue(ResilientLLMProvider.isPermanentClientError(400))
        XCTAssertTrue(ResilientLLMProvider.isPermanentClientError(404))
        XCTAssertFalse(ResilientLLMProvider.isPermanentClientError(408))
        XCTAssertFalse(ResilientLLMProvider.isPermanentClientError(429))
        XCTAssertFalse(ResilientLLMProvider.isPermanentClientError(500))
    }

    // MARK: Cache

    func testFailedModuleIsNotCached() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("llm_cache_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let key = OutputCacheKey(term: "orbit", mode: "Word", detail: "Short", domain: "General", provider: "P", model: "M")

        let first = InspectorViewModel(cacheFileURL: url)
        Self.retained.append(first)
        first.outputs[.definitionEN] = "a circular path"
        first.outputs[.etymologyEN] = "From Latin orb"
        first.errors[.etymologyEN] = "Cannot reach the AI server."
        first.snapshotToCache(key: key)

        let second = InspectorViewModel(cacheFileURL: url)
        Self.retained.append(second)
        XCTAssertTrue(second.loadFromCache(key: key))
        XCTAssertEqual(second.outputs[.definitionEN], "a circular path")
        XCTAssertNil(second.outputs[.etymologyEN], "the half answer must not come back as a cache hit")
    }

    // MARK: SSE parsing

    func testSSEPayloadAcceptsOptionalSpace() async {
        XCTAssertEqual(LLMSessionPool.ssePayload("data: {\"a\":1}"), "{\"a\":1}")
        XCTAssertEqual(LLMSessionPool.ssePayload("data:{\"a\":1}"), "{\"a\":1}")
        XCTAssertNil(LLMSessionPool.ssePayload("event: message_stop"))
        XCTAssertNil(LLMSessionPool.ssePayload(": keep-alive"))
    }

    func testSessionsAreSharedPerTimeout() async {
        XCTAssertTrue(LLMClient.makeSession(timeout: 42) === LLMClient.makeSession(timeout: 42))
        XCTAssertTrue(AnthropicClient.makeSession(timeout: 42) === LLMClient.makeSession(timeout: 42))
        XCTAssertFalse(LLMClient.makeSession(timeout: 42) === LLMClient.makeSession(timeout: 43))
    }

    private func stubbedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        Self.retained.append(session)
        return session
    }

    func testOpenAIStreamParsesDataLinesWithoutSpace() async throws {
        StubURLProtocol.status = 200
        StubURLProtocol.body = Data("""
        data:{"choices":[{"delta":{"content":"Hel"},"finish_reason":null}]}

        data: {"choices":[{"delta":{"content":"lo"},"finish_reason":"stop"}]}

        data: [DONE]

        """.utf8)
        var client = LLMClient()
        client.baseURLString = "https://example.invalid"
        client.session = stubbedSession()

        let output = try await collect(client)
        XCTAssertEqual(output, "Hello")
    }

    func testStreamErrorCarriesTheServerMessage() async throws {
        StubURLProtocol.status = 404
        StubURLProtocol.body = Data(#"{"error":{"message":"model 'nope' not found"}}"#.utf8)
        var client = LLMClient()
        client.baseURLString = "https://example.invalid"
        client.session = stubbedSession()

        do {
            _ = try await collect(client)
            XCTFail("a 404 should throw")
        } catch LLMClient.ClientError.badStatusCode(let status, let body) {
            XCTAssertEqual(status, 404)
            XCTAssertTrue(body.contains("not found"), body)
        }
    }

    // MARK: Anthropic request shape

    private func anthropicBody(model: String, maxTokens: Int = 300) throws -> [String: Any] {
        var client = AnthropicClient()
        client.model = model
        client.apiKey = "test"
        let request = try client.buildRequest(
            system: "s", user: "u", temperature: 0.2, maxTokens: maxTokens, topP: 0.9, stream: true
        )
        return try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }

    func testAnthropicNeverSendsTopP() async throws {
        for model in ["claude-haiku-4-5", "claude-sonnet-4-6", "claude-opus-5", "claude-sonnet-4-20250514"] {
            XCTAssertNil(try anthropicBody(model: model)["top_p"], model)
        }
    }

    func testOlderClaudeKeepsTemperature() async throws {
        let body = try anthropicBody(model: "claude-sonnet-4-5")
        XCTAssertEqual(body["temperature"] as? Double, 0.2)
        XCTAssertNil(body["output_config"])
        XCTAssertEqual(body["max_tokens"] as? Int, 300)
    }

    func testCurrentClaudeGetsLowEffortAndThinkingHeadroom() async throws {
        for model in ["claude-opus-5", "claude-opus-5-5", "claude-sonnet-5", "claude-fable-5-1", "claude-opus-6"] {
            let body = try anthropicBody(model: model)
            XCTAssertNil(body["temperature"], model)
            XCTAssertEqual((body["output_config"] as? [String: Any])?["effort"] as? String, "low", model)
            XCTAssertEqual(body["max_tokens"] as? Int, 300 + AnthropicModelTraits.thinkingHeadroom, model)
        }
    }

    func testOpus48RejectsSamplingButDoesNotThinkByDefault() async throws {
        let body = try anthropicBody(model: "claude-opus-4-8")
        XCTAssertNil(body["temperature"])
        XCTAssertEqual(body["max_tokens"] as? Int, 300)
    }
}
