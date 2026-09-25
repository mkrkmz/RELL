//
//  InspectorRunTests.swift
//  Reader for Language LearnerTests
//
//  v1.41: module requests and Ask AI now run in InspectorViewModel, where
//  they can be tested without a view — streaming, errors, truncation,
//  caching, and the stale-request race the move uncovered.
//

import XCTest
@testable import Reader_for_Language_Learner

/// Emits tokens with a pause between them, then optionally fails.
@MainActor
private final class SlowProvider: LLMProvider {
    let tokens: [String]
    let error: Error?
    let pause: Duration
    let finishReason: LLMFinishReason?

    init(_ tokens: [String], error: Error? = nil, pause: Duration = .milliseconds(5), finishReason: LLMFinishReason? = .stop) {
        self.tokens = tokens
        self.error = error
        self.pause = pause
        self.finishReason = finishReason
    }

    func chat(system: String, user: String, temperature: Double, maxTokens: Int, topP: Double) async throws -> String { "" }

    func stream(
        system: String, user: String, temperature: Double, maxTokens: Int, topP: Double,
        onToken: @MainActor @escaping (String) -> Void
    ) async throws -> LLMFinishReason? {
        for token in tokens {
            // Deliberately not checking cancellation: a real stream can still
            // deliver a token or two after its task is cancelled.
            try? await Task.sleep(for: pause)
            onToken(token)
        }
        if let error { throw error }
        return finishReason
    }
}

@MainActor
final class InspectorRunTests: XCTestCase {
    private static var retained: [AnyObject] = []

    private func makeViewModel() -> InspectorViewModel {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("inspector_run_\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let viewModel = InspectorViewModel(cacheFileURL: url)
        Self.retained.append(viewModel)
        return viewModel
    }

    private let key = OutputCacheKey(term: "orbit", mode: "Word", detail: "Short", domain: "General", provider: "P", model: "M")

    private func run(_ module: ModuleType = .definitionEN, maxTokens: Int = 200, isFallback: Bool = false) -> InspectorViewModel.ModuleRun {
        InspectorViewModel.ModuleRun(
            module: module, system: "s", user: "u", temperature: 0.1, maxTokens: maxTokens,
            cacheKey: key, isFallback: isFallback, usesLocalGate: false
        )
    }

    private func waitUntilIdle(_ viewModel: InspectorViewModel, _ module: ModuleType = .definitionEN) async {
        for _ in 0..<200 where viewModel.loading[module] == true || viewModel.activeTasks[module] != nil {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func testStreamedAnswerIsAssembledTimedAndCached() async {
        let viewModel = makeViewModel()
        viewModel.start(run(), provider: SlowProvider(["a circular ", "path"]))
        XCTAssertEqual(viewModel.loading[.definitionEN], true)
        await waitUntilIdle(viewModel)

        XCTAssertEqual(viewModel.outputs[.definitionEN], "a circular path")
        XCTAssertNil(viewModel.errors[.definitionEN])
        XCTAssertEqual(viewModel.wasTruncated[.definitionEN], false)
        XCTAssertNotNil(viewModel.moduleElapsed[.definitionEN])
        XCTAssertEqual(viewModel.cache.get(key)?[.definitionEN], "a circular path")
    }

    func testFallbackFailureExplainsWhyTheServerWasNeeded() async {
        let viewModel = makeViewModel()
        viewModel.start(run(.etymologyEN, isFallback: true),
                        provider: SlowProvider([], error: LLMClient.ClientError.serverNotReachable))
        await waitUntilIdle(viewModel, .etymologyEN)

        let message = viewModel.errors[.etymologyEN] ?? ""
        XCTAssertTrue(message.contains("isn't reliable for this module"), message)
        XCTAssertNil(viewModel.cache.get(key)?[.etymologyEN])
    }

    /// Found while moving this code out of the view: re-running a module
    /// cancelled the old request, which then finished and wrote
    /// `loading = false` and its late tokens over the new request.
    func testACancelledRequestCannotTouchItsReplacement() async {
        let viewModel = makeViewModel()
        viewModel.start(run(), provider: SlowProvider(["old ", "old ", "old"], pause: .milliseconds(30)))
        try? await Task.sleep(for: .milliseconds(10))
        viewModel.start(run(), provider: SlowProvider(["new ", "answer"], pause: .milliseconds(80)))

        try? await Task.sleep(for: .milliseconds(120))   // the old stream ends meanwhile
        XCTAssertEqual(viewModel.loading[.definitionEN], true, "the new request is still running")
        XCTAssertNotNil(viewModel.activeTasks[.definitionEN])

        await waitUntilIdle(viewModel)
        XCTAssertEqual(viewModel.outputs[.definitionEN], "new answer")
    }

    func testUserCancelStopsLoadingAndDropsLateTokens() async {
        let viewModel = makeViewModel()
        viewModel.start(run(), provider: SlowProvider(["a", "b", "c"], pause: .milliseconds(20)))
        try? await Task.sleep(for: .milliseconds(30))
        viewModel.cancel(module: .definitionEN)
        let atCancel = viewModel.outputs[.definitionEN]
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(viewModel.loading[.definitionEN], false)
        XCTAssertEqual(viewModel.outputs[.definitionEN], atCancel)
        XCTAssertNil(viewModel.moduleElapsed[.definitionEN])
    }

    func testTruncationUsesTheFinishReasonThenTheBudget() async {
        XCTAssertTrue(InspectorViewModel.looksTruncated(finishReason: .length, outputLength: 1, maxTokens: 100))
        XCTAssertFalse(InspectorViewModel.looksTruncated(finishReason: .stop, outputLength: 10_000, maxTokens: 100))
        XCTAssertTrue(InspectorViewModel.looksTruncated(finishReason: nil, outputLength: 315, maxTokens: 100))
        XCTAssertFalse(InspectorViewModel.looksTruncated(finishReason: nil, outputLength: 200, maxTokens: 100))
    }

    func testFollowUpStreamsIntoItsExchange() async {
        let viewModel = makeViewModel()
        viewModel.startFollowUp(question: "why?", system: "s", provider: SlowProvider(["because ", "of that"]), usesLocalGate: false)
        XCTAssertTrue(viewModel.isAskingFollowUp)
        for _ in 0..<100 where viewModel.isAskingFollowUp { try? await Task.sleep(for: .milliseconds(10)) }

        XCTAssertEqual(viewModel.followUps.count, 1)
        XCTAssertEqual(viewModel.followUps.first?.answer, "because of that")
        XCTAssertNil(viewModel.followUps.first?.error)
        XCTAssertNil(viewModel.followUpTask)
    }

    func testANewFollowUpKeepsItsTaskWhenTheOldOneEnds() async {
        let viewModel = makeViewModel()
        viewModel.startFollowUp(question: "one", system: "s", provider: SlowProvider(["1", "1"], pause: .milliseconds(20)), usesLocalGate: false)
        viewModel.startFollowUp(question: "two", system: "s", provider: SlowProvider(["2", "2"], pause: .milliseconds(60)), usesLocalGate: false)
        try? await Task.sleep(for: .milliseconds(70))

        XCTAssertNotNil(viewModel.followUpTask, "the first exchange ending must not clear the second's task")
        for _ in 0..<100 where viewModel.isAskingFollowUp { try? await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(viewModel.followUps.last?.answer, "22")
    }
}
