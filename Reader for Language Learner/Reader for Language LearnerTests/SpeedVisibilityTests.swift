//
//  SpeedVisibilityTests.swift
//  Reader for Language LearnerTests
//
//  v17 Sprint 2 — the line under an answer (engine, timing and why it was
//  slow), the speed test's arithmetic and its advice, and where an answer
//  came from.
//

import SwiftUI
import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class SpeedVisibilityTests: XCTestCase {

    private func record(
        engine: String = "LM Studio", model: String? = "google/gemma-4-e4b", onThisMac: Bool = true,
        wait: TimeInterval = 0, first: TimeInterval = 0.3, total: TimeInterval = 0.7,
        outcome: LLMRequestRecord.Outcome? = .finished
    ) -> LLMRequestRecord {
        let queued = Date(timeIntervalSinceReferenceDate: 0)
        let started = queued.addingTimeInterval(wait)
        var record = LLMRequestRecord(id: UUID(), origin: .module, detail: nil, engine: engine, model: model,
                                      onThisMac: onThisMac, queuedAt: queued)
        record.startedAt = started
        record.firstTokenAt = started.addingTimeInterval(first)
        record.finishedAt = queued.addingTimeInterval(total)
        record.outcome = outcome
        return record
    }

    // MARK: Footer

    func testAQuickAnswerSaysWhoAnsweredAndNothingMore() throws {
        let local = try XCTUnwrap(AnswerFooter.make(record()))
        XCTAssertEqual(local.engine, .provider(name: "LM Studio", model: "google/gemma-4-e4b"))
        XCTAssertNil(local.flag)
        XCTAssertEqual(try XCTUnwrap(local.firstToken), 0.3, accuracy: 0.001)

        let apple = try XCTUnwrap(AnswerFooter.make(record(engine: AppleOnDevice.providerLabel, model: nil, onThisMac: false)))
        XCTAssertEqual(apple.engine, .apple)
        XCTAssertNil(apple.flag)
    }

    func testASlowAnswerSaysWhy() throws {
        XCTAssertEqual(AnswerFooter.make(record(wait: 3.2, first: 0.6, total: 4.1))?.flag, .waited(3.2))
        XCTAssertEqual(AnswerFooter.make(record(first: 12.4, total: 12.8))?.flag, .modelLoaded(12.4))
        XCTAssertEqual(AnswerFooter.make(record(engine: "Ollama", model: "gemma4:31b-cloud", onThisMac: false,
                                                first: 6, total: 7))?.flag, .slowCloud(6))
        XCTAssertNil(AnswerFooter.make(record(engine: AppleOnDevice.providerLabel, model: nil, onThisMac: false,
                                              first: 6, total: 7))?.flag, "Apple's model is never a slow cloud")
    }

    func testWaitingIsTheReasonEvenWhenTheModelThenLoaded() {
        XCTAssertEqual(AnswerFooter.make(record(wait: 2, first: 9, total: 12))?.flag, .waited(2))
    }

    func testNoFooterForAFailedOrUnfinishedRequest() {
        XCTAssertNil(AnswerFooter.make(record(outcome: .failed("URLError -1001"))))
        XCTAssertNil(AnswerFooter.make(record(outcome: .cancelled)))
        XCTAssertNil(AnswerFooter.make(record(outcome: nil)))
    }

    func testTheFooterStaysOneLineInANarrowColumn() {
        let footer = AnswerFooter(engine: .provider(name: "OpenAI Compatible", model: "a-very-long-provider/model-name-that-goes-on-and-on"),
                                  isCached: false, firstToken: 0.4, total: 3.2, flag: .waited(2.9))
        let view = AnswerFooterView(footer: footer, onExplain: {}).frame(width: 220)
        let height = NSHostingView(rootView: view).fittingSize.height
        XCTAssertLessThan(height, 30, "the footer wrapped to \(height) pt; it must stay one line")
    }

    // MARK: Where an answer came from

    func testTheInspectorRemembersWhereEachAnswerCameFrom() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("speed_\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let viewModel = InspectorViewModel(cacheFileURL: url)
        let key = OutputCacheKey(term: "orbit", mode: "Word", detail: "Short", domain: "General", provider: "P", model: "M")
        let log = LLMRequestLog()
        let provider = log.recording(Echo(), origin: .module, detail: ModuleType.definitionEN.rawValue, route: .appleOnDevice)

        viewModel.start(InspectorViewModel.ModuleRun(module: .definitionEN, system: "s", user: "a path", temperature: 0,
                                                     maxTokens: 50, cacheKey: key, isFallback: false),
                        provider: provider)
        XCTAssertEqual(viewModel.answerSources[.definitionEN], .request(provider.id))
        for _ in 0..<200 where viewModel.loading[.definitionEN] == true { try await Task.sleep(for: .milliseconds(5)) }

        viewModel.resetAll()
        XCTAssertNil(viewModel.answerSources[.definitionEN])
        XCTAssertTrue(viewModel.loadFromCache(key: key))
        XCTAssertEqual(viewModel.answerSources[.definitionEN], .cached)
        withExtendedLifetime(viewModel) {}
    }

    // MARK: Speed test

    func testTheLoadIsTheFirstRequestsExtraTime() {
        XCTAssertEqual(try XCTUnwrap(SpeedTest.loadTime(cold: 12.4, warm: 0.3)), 12.1, accuracy: 0.001)
        XCTAssertNil(SpeedTest.loadTime(cold: 0.9, warm: 0.3), "noise, not a load")
        XCTAssertNil(SpeedTest.loadTime(cold: nil, warm: 0.3))
    }

    func testWordsPerSecondCountFromTheFirstWord() throws {
        let measured = record(first: 1, total: 3)   // writing took 2 s
        let speed = try XCTUnwrap(SpeedTest.wordsPerSecond(answer: "one two three four five six", record: measured))
        XCTAssertEqual(speed, 3, accuracy: 0.001)
        XCTAssertNil(SpeedTest.wordsPerSecond(answer: "hi", record: measured), "too short to say")
    }

    func testOllamasModelSizeIsReadFromItsList() throws {
        let json = #"{"models":[{"name":"gemma4:12b-mlx","model":"gemma4:12b-mlx","size":8003321808}]}"#
        XCTAssertEqual(SpeedTest.ollamaModelBytes(fromPS: Data(json.utf8), model: "gemma4:12b-mlx"), 8_003_321_808)
        XCTAssertNil(SpeedTest.ollamaModelBytes(fromPS: Data(json.utf8), model: "other"))
    }

    // MARK: Advice

    private func result(engine: String = "Ollama", model: String? = "gemma4:12b", isApple: Bool = false, onThisMac: Bool = true,
                        load: TimeInterval? = nil, first: TimeInterval? = 0.6, speed: Double? = 30,
                        bytes: Int64? = nil, failure: String? = nil) -> SpeedTest.Result {
        SpeedTest.Result(engine: engine, model: model, isApple: isApple, onThisMac: onThisMac, load: load,
                         firstToken: first, wordsPerSecond: speed, modelBytes: bytes, failure: failure)
    }

    private let sixteenGB: UInt64 = 16 * 1_073_741_824

    func testAllGoodWhenNothingIsWrong() {
        let items = SpeedAdvice.items(apple: .on, results: [result()], physicalMemory: sixteenGB)
        XCTAssertEqual(items.map(\.kind), [.good])
    }

    func testAppleOffAndABigSlowModelAreBothSaid() {
        let items = SpeedAdvice.items(apple: .unavailable(reason: "Turn on Apple Intelligence."),
                                      results: [result(load: 14.8, speed: 9, bytes: 8_003_321_808)],
                                      physicalMemory: sixteenGB)
        XCTAssertEqual(items.map(\.kind), [.warning, .warning, .info])
        XCTAssertTrue(items[0].detail.hasPrefix("Turn on Apple Intelligence."))
        XCTAssertTrue(items[1].detail.contains("GB"), "names the model size: \(items[1].detail)")
        XCTAssertFalse(items.contains { $0.kind == .good })
    }

    func testASlowCloudModelPointsAwayFromThisMac() {
        let cloud = result(model: "gemma4:31b-cloud", onThisMac: false, first: 6.5, speed: 40)
        let items = SpeedAdvice.items(apple: .on, results: [cloud], physicalMemory: sixteenGB)
        XCTAssertEqual(items.map(\.kind), [.warning])
        XCTAssertNil(SpeedAdvice.items(apple: .on, results: [result(model: "gemma4:31b-cloud", onThisMac: false, first: 0.4)],
                                       physicalMemory: sixteenGB).first { $0.kind == .warning })
    }

    func testAFailedEngineIsSaid() {
        let items = SpeedAdvice.items(apple: .offInRELL, results: [result(first: nil, speed: nil, failure: "Not reachable")],
                                      physicalMemory: sixteenGB)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[1].detail, "Not reachable")
    }

    private struct Echo: LLMProvider {
        func chat(system: String, user: String, temperature: Double, maxTokens: Int, topP: Double) async throws -> String { user }
        func stream(system: String, user: String, temperature: Double, maxTokens: Int, topP: Double,
                    onToken: @MainActor @escaping (String) -> Void) async throws -> LLMFinishReason? {
            onToken(user)
            return .stop
        }
    }
}

// MARK: - A word looked up before

@MainActor
final class SavedAnswerOpeningTests: XCTestCase {
    private let all: (ModuleType) -> Bool = { _ in true }

    func testAWordWithSavedAnswersOpensOnTheModuleUsedLast() {
        let outputs: [ModuleType: String] = [.definitionEN: "a", .examplesEN: "b"]
        XCTAssertEqual(InspectorViewModel.moduleToShow(active: nil, lastUsed: .examplesEN, primary: ModuleType.primary,
                                                       outputs: outputs, isEnabled: all), .examplesEN)
    }

    func testOtherwiseOnTheFirstModuleThatHasAnAnswer() {
        let outputs: [ModuleType: String] = [.examplesEN: "b"]
        XCTAssertEqual(InspectorViewModel.moduleToShow(active: nil, lastUsed: .collocations, primary: ModuleType.primary,
                                                       outputs: outputs, isEnabled: all), .examplesEN)
        XCTAssertEqual(InspectorViewModel.moduleToShow(active: .collocations, lastUsed: .collocations, primary: ModuleType.primary,
                                                       outputs: outputs, isEnabled: all), .examplesEN,
                       "an open module without an answer gives way to one with")
    }

    func testAnOpenModuleWithAnAnswerStays() {
        let outputs: [ModuleType: String] = [.definitionEN: "a", .examplesEN: "b"]
        XCTAssertEqual(InspectorViewModel.moduleToShow(active: .definitionEN, lastUsed: .examplesEN, primary: ModuleType.primary,
                                                       outputs: outputs, isEnabled: all), .definitionEN)
    }

    func testADisabledModuleIsSkipped() {
        let outputs: [ModuleType: String] = [.etymologyEN: "a", .definitionEN: "b"]
        XCTAssertEqual(InspectorViewModel.moduleToShow(active: nil, lastUsed: .etymologyEN, primary: ModuleType.primary,
                                                       outputs: outputs, isEnabled: { $0 != .etymologyEN }), .definitionEN)
    }
}
