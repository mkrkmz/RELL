//
//  SpeechManagerTests.swift
//  Reader for Language LearnerTests
//

import AVFoundation
import XCTest
@testable import Reader_for_Language_Learner

// SpeechManager has a private init and is only ever the `.shared` singleton
// (no per-test isolation the way file-backed stores get) — the CI static-
// retained-array convention doesn't apply here since nothing is freshly
// created. Every test resets to `.idle` in tearDown to avoid bleeding state
// into the next test. Delegate methods are invoked directly (never through
// `speak()`) so these tests never trigger real speech synthesis.
@MainActor
final class SpeechManagerTests: XCTestCase {
    private var manager: SpeechManager { SpeechManager.shared }

    override func tearDown() {
        manager.stop()
        super.tearDown()
    }

    // MARK: - Sentence splitting

    func testSentenceSplitOnMultipleSentences() {
        let sentences = SpeechManager.sentenceSplit("Hello world. This is a test! Are you sure?")
        XCTAssertEqual(sentences, ["Hello world.", "This is a test!", "Are you sure?"])
    }

    func testSentenceSplitFallsBackToWholeStringForBareWord() {
        XCTAssertEqual(SpeechManager.sentenceSplit("pseudo"), ["pseudo"])
    }

    func testSentenceSplitTrimsWhitespaceAroundSentences() {
        let sentences = SpeechManager.sentenceSplit("  First one.   Second one.  ")
        XCTAssertEqual(sentences, ["First one.", "Second one."])
    }

    // MARK: - Delegate-driven state transitions

    func testDidStartSetsSpeakingState() async {
        manager.stop()
        XCTAssertEqual(manager.state, .idle)

        let utterance = AVSpeechUtterance(string: "test")
        manager.speechSynthesizer(AVSpeechSynthesizer(), didStart: utterance)
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(manager.state, .speaking)
    }

    func testDidPauseAndDidContinueToggleState() async {
        let dummySynth = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: "test")
        manager.speechSynthesizer(dummySynth, didStart: utterance)
        try? await Task.sleep(for: .milliseconds(50))

        manager.speechSynthesizer(dummySynth, didPause: utterance)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(manager.state, .paused)

        manager.speechSynthesizer(dummySynth, didContinue: utterance)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(manager.state, .speaking)
    }

    func testDidFinishSetsIdleWhenSynthesizerHasNothingQueued() async {
        // A synthesizer nobody ever called .speak() on reports isSpeaking
        // == false, which is exactly the "that was the last utterance"
        // case didFinish needs to distinguish from "more are queued".
        let dummySynth = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: "test")
        manager.speechSynthesizer(dummySynth, didStart: utterance)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(manager.state, .speaking)

        manager.speechSynthesizer(dummySynth, didFinish: utterance)
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(manager.state, .idle)
        XCTAssertNil(manager.progress)
    }

    func testDidCancelResetsToIdle() async {
        let dummySynth = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: "test")
        manager.speechSynthesizer(dummySynth, didStart: utterance)
        try? await Task.sleep(for: .milliseconds(50))

        manager.speechSynthesizer(dummySynth, didCancel: utterance)
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(manager.state, .idle)
        XCTAssertNil(manager.progress)
    }

    // MARK: - Idempotent controls

    func testPauseIsNoOpWhenIdle() {
        manager.stop()
        manager.pause()
        XCTAssertEqual(manager.state, .idle)
    }

    func testResumeIsNoOpWhenNotPaused() {
        manager.stop()
        manager.resume()
        XCTAssertEqual(manager.state, .idle)
    }
}
