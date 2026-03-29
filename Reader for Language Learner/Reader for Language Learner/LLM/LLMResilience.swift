//
//  LLMResilience.swift
//  Reader for Language Learner
//
//  Retry with exponential backoff and circuit breaker for LLM providers.
//

import Foundation
import os

// MARK: - Circuit Breaker

@MainActor
@Observable
final class CircuitBreaker {
    enum State: String {
        case closed   // Normal — requests pass through
        case open     // Tripped — requests fail fast
        case halfOpen // Testing — one request allowed through
    }

    private(set) var state: State = .closed
    private var failureCount = 0
    private var lastFailureDate: Date?

    let failureThreshold: Int
    let resetTimeout: TimeInterval

    init(failureThreshold: Int = 3, resetTimeout: TimeInterval = 30) {
        self.failureThreshold = failureThreshold
        self.resetTimeout = resetTimeout
    }

    var isAvailable: Bool {
        switch state {
        case .closed:
            return true
        case .open:
            if let last = lastFailureDate, Date().timeIntervalSince(last) >= resetTimeout {
                state = .halfOpen
                return true
            }
            return false
        case .halfOpen:
            return true
        }
    }

    func recordSuccess() {
        failureCount = 0
        state = .closed
    }

    func recordFailure() {
        failureCount += 1
        lastFailureDate = Date()
        if failureCount >= failureThreshold {
            state = .open
            AppLogger.llm.warning("Circuit breaker opened after \(self.failureCount) failures")
        }
    }

    func reset() {
        failureCount = 0
        state = .closed
        lastFailureDate = nil
    }
}

// MARK: - Resilient LLM Provider

/// Wraps any LLMProvider with retry logic and circuit breaker.
struct ResilientLLMProvider: LLMProvider {
    let inner: any LLMProvider
    let circuitBreaker: CircuitBreaker
    let maxRetries: Int
    let baseDelay: TimeInterval

    init(
        provider: any LLMProvider,
        circuitBreaker: CircuitBreaker,
        maxRetries: Int = 2,
        baseDelay: TimeInterval = 1.0
    ) {
        self.inner = provider
        self.circuitBreaker = circuitBreaker
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
    }

    func chat(
        system: String,
        user: String,
        temperature: Double,
        maxTokens: Int,
        topP: Double
    ) async throws -> String {
        try await withRetry {
            try await inner.chat(
                system: system,
                user: user,
                temperature: temperature,
                maxTokens: maxTokens,
                topP: topP
            )
        }
    }

    func stream(
        system: String,
        user: String,
        temperature: Double,
        maxTokens: Int,
        topP: Double,
        onToken: @MainActor @escaping (String) -> Void
    ) async throws {
        try await withRetry {
            try await inner.stream(
                system: system,
                user: user,
                temperature: temperature,
                maxTokens: maxTokens,
                topP: topP,
                onToken: onToken
            )
        }
    }

    // MARK: - Retry Logic

    private func withRetry<T>(_ operation: () async throws -> T) async throws -> T {
        guard await circuitBreaker.isAvailable else {
            throw LLMResilienceError.circuitOpen
        }

        var lastError: Error?

        for attempt in 0...maxRetries {
            do {
                try Task.checkCancellation()
                let result = try await operation()
                await circuitBreaker.recordSuccess()
                return result
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error

                // Don't retry auth errors or invalid URLs
                if isNonRetryable(error) {
                    await circuitBreaker.recordFailure()
                    throw error
                }

                await circuitBreaker.recordFailure()

                if attempt < maxRetries {
                    let delay = baseDelay * pow(2.0, Double(attempt))
                    AppLogger.llm.info("Retry \(attempt + 1)/\(self.maxRetries) after \(delay)s")
                    try await Task.sleep(for: .seconds(delay))
                }
            }
        }

        throw lastError ?? LLMResilienceError.allRetriesFailed
    }

    private func isNonRetryable(_ error: Error) -> Bool {
        if let clientError = error as? LLMClient.ClientError {
            switch clientError {
            case .invalidURL, .unauthorized:
                return true
            case .serverNotReachable, .badStatusCode, .invalidResponse:
                return false
            }
        }
        if let anthropicError = error as? AnthropicClient.ClientError {
            switch anthropicError {
            case .invalidURL, .unauthorized:
                return true
            case .serverNotReachable, .badStatusCode, .invalidResponse:
                return false
            }
        }
        return false
    }
}

// MARK: - Error

enum LLMResilienceError: LocalizedError {
    case circuitOpen
    case allRetriesFailed

    var errorDescription: String? {
        switch self {
        case .circuitOpen:
            return "LLM server appears to be down. Waiting before retrying — please check your server."
        case .allRetriesFailed:
            return "All retry attempts failed. Please check your LLM server connection."
        }
    }
}
