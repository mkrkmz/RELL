//
//  EveryMacTests.swift
//  Reader for Language LearnerTests
//
//  v17 Sprint 3 — the update check (versions, GitHub's answer, once a day,
//  never on a local build), the diagnostic report (what it says and what it
//  leaves out) and the model size hint.
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class EveryMacTests: XCTestCase {

    // MARK: Update check

    func testVersionsCompareByNumber() {
        XCTAssertTrue(UpdateChecker.isNewer("v1.47.0", than: "1.46.1"))
        XCTAssertTrue(UpdateChecker.isNewer("1.46.10", than: "1.46.9"), "not alphabetical")
        XCTAssertTrue(UpdateChecker.isNewer("2.0", than: "1.99.9"))
        XCTAssertFalse(UpdateChecker.isNewer("1.46.1", than: "1.46.1"))
        XCTAssertFalse(UpdateChecker.isNewer("1.46", than: "1.46.0"), "a missing part counts as 0")
        XCTAssertFalse(UpdateChecker.isNewer("1.45.0", than: "1.46.1"))
    }

    func testALocalBuildNeverChecks() {
        XCTAssertFalse(UpdateChecker.isReleaseBuild("1.0"), "Xcode's own builds")
        XCTAssertFalse(UpdateChecker.isReleaseBuild(""))
        XCTAssertTrue(UpdateChecker.isReleaseBuild("1.46.1"))
    }

    func testAtMostOnceADay() {
        let now = Date()
        XCTAssertTrue(UpdateChecker.isDue(lastCheck: nil, now: now))
        XCTAssertFalse(UpdateChecker.isDue(lastCheck: now.addingTimeInterval(-3_600), now: now))
        XCTAssertTrue(UpdateChecker.isDue(lastCheck: now.addingTimeInterval(-25 * 3_600), now: now))
    }

    func testGitHubsAnswerIsRead() throws {
        let json = #"{"tag_name":"v1.47.0","html_url":"https://github.com/mkrkmz/RELL/releases/tag/v1.47.0","body":"Added\n- Speed","draft":false,"prerelease":false}"#
        let release = try XCTUnwrap(UpdateChecker.release(from: Data(json.utf8)))
        XCTAssertEqual(release.version, "1.47.0")
        XCTAssertEqual(release.pageURL.absoluteString, "https://github.com/mkrkmz/RELL/releases/tag/v1.47.0")
        XCTAssertEqual(release.notes, "Added\n- Speed")
    }

    func testPreReleasesAndDraftsDontCount() {
        XCTAssertNil(UpdateChecker.release(from: Data(#"{"tag_name":"v2.0.0","prerelease":true}"#.utf8)))
        XCTAssertNil(UpdateChecker.release(from: Data(#"{"tag_name":"v2.0.0","draft":true}"#.utf8)))
        XCTAssertNil(UpdateChecker.release(from: Data(#"{"message":"Not Found"}"#.utf8)))
    }

    // MARK: Diagnostic report

    private func facts(serverURL: String, onThisMac: Bool, requests: [LLMRequestRecord] = []) -> DiagnosticReport.Facts {
        DiagnosticReport.Facts(
            date: Date(timeIntervalSinceReferenceDate: 0), appVersion: "1.47.0", macOS: "26.1", chip: "Apple M4",
            memoryBytes: 16 * 1_073_741_824, appleUnavailableReason: "Turn on Apple Intelligence in System Settings to use it.",
            appleOnInRELL: true, providerType: "Ollama", model: "gemma4:31b-cloud", onThisMac: onThisMac,
            serverURL: serverURL, ollamaVersion: "0.11.4", timeout: 30,
            speedResults: [SpeedTest.Result(engine: "Ollama", model: "gemma4:31b-cloud", isApple: false, onThisMac: false,
                                            load: nil, firstToken: 6.4, wordsPerSecond: 38, modelBytes: nil, failure: nil)],
            requests: requests
        )
    }

    func testTheReportSaysWhatsSetUpAndHowLongThingsTook() {
        var record = LLMRequestRecord(id: UUID(), origin: .module, detail: "definitionEN", engine: "Ollama",
                                      model: "gemma4:31b-cloud", queuedAt: Date())
        record.startedAt = record.queuedAt
        record.firstTokenAt = record.queuedAt.addingTimeInterval(6.1)
        record.finishedAt = record.queuedAt.addingTimeInterval(6.9)
        record.outcome = .finished
        let text = DiagnosticReport.text(facts(serverURL: "http://127.0.0.1:11434", onThisMac: false, requests: [record]))
        for expected in ["1.47.0", "26.1", "Apple M4", "Turn on Apple Intelligence", "gemma4:31b-cloud",
                         "127.0.0.1:11434", "0.11.4", "module/definitionEN", "6.9"] {
            XCTAssertTrue(text.contains(expected) || text.contains(expected.replacingOccurrences(of: ".", with: ",")),
                          "missing \(expected) in:\n\(text)")
        }
    }

    func testARemoteServersAddressStaysOut() {
        let text = DiagnosticReport.text(facts(serverURL: "https://llm.my-company.internal/v1", onThisMac: false))
        XCTAssertFalse(text.contains("my-company"), text)
        XCTAssertNil(DiagnosticReport.localAddress("https://api.openai.com"))
        XCTAssertEqual(DiagnosticReport.localAddress("http://localhost:1234"), "localhost:1234")
    }

    // MARK: First run

    func testTheModelSizeHintFollowsMemory() {
        let gb: UInt64 = 1_073_741_824
        XCTAssertTrue(SpeedAdvice.modelSizeHint(memoryBytes: 8 * gb).contains("1–4B"))
        XCTAssertTrue(SpeedAdvice.modelSizeHint(memoryBytes: 16 * gb).contains("4–8B"))
        XCTAssertTrue(SpeedAdvice.modelSizeHint(memoryBytes: 32 * gb).contains("8–14B"))
        XCTAssertTrue(SpeedAdvice.modelSizeHint(memoryBytes: 64 * gb).contains("14–32B"))
    }
}
