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

    // MARK: - Spoken-sentence tracking (karaoke, L4)

    func testSpokenSentenceIsNilWhenIdle() {
        manager.stop()
        XCTAssertNil(manager.spokenSentence)
    }

    func testStopClearsSpokenSentence() {
        manager.stop()
        XCTAssertNil(manager.spokenSentence, "stopping must clear the karaoke highlight source")
    }

    /// A rate change cancels and re-enqueues, so `didStart` fires for
    /// utterances the manager may not have bookkeeping for. That must never
    /// publish a bogus sentence for the reader to highlight.
    func testDidStartWithUnknownUtteranceLeavesSpokenSentenceNil() async {
        manager.stop()

        let stray = AVSpeechUtterance(string: "not from the queue")
        manager.speechSynthesizer(AVSpeechSynthesizer(), didStart: stray)
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertNil(manager.spokenSentence)
        XCTAssertEqual(manager.state, .speaking, "state still tracks playback")
    }

    func testDidFinishClearsSpokenSentenceWhenNothingIsQueued() async {
        manager.stop()
        let idleSynth = AVSpeechSynthesizer()

        manager.speechSynthesizer(idleSynth, didFinish: AVSpeechUtterance(string: "done"))
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertNil(manager.spokenSentence)
        XCTAssertEqual(manager.state, .idle)
    }

    func testDidCancelClearsSpokenSentenceWhenNothingIsQueued() async {
        manager.stop()
        let idleSynth = AVSpeechSynthesizer()

        manager.speechSynthesizer(idleSynth, didCancel: AVSpeechUtterance(string: "cancelled"))
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertNil(manager.spokenSentence)
    }

    /// The sentences fed to karaoke come from this split, so a passage the
    /// reader hears as one line must be one highlightable unit.
    func testSentenceSplitProducesUnitsSuitableForKaraoke() {
        let sentences = SpeechManager.sentenceSplit("The cat sat. The dog ran.")
        XCTAssertEqual(sentences.count, 2)
        XCTAssertTrue(sentences.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
    }

    // MARK: - Karaoke highlight styling

    func testKaraokeBackgroundAdaptsToPageTheme() {
        let onLightInk = EPUBViewManager.karaokeBackground(for: .dark)
        let onDarkInk = EPUBViewManager.karaokeBackground(for: .original)
        XCTAssertFalse(onLightInk.isEmpty)
        XCTAssertFalse(onDarkInk.isEmpty)
        XCTAssertNotEqual(onLightInk, onDarkInk, "the wash must differ between light- and dark-ink themes")
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
