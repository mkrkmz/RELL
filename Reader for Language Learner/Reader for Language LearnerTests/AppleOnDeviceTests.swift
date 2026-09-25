//
//  AppleOnDeviceTests.swift
//  Reader for Language LearnerTests
//
//  v1.40: which requests Apple's on-device model answers, and the sentence
//  strip's Apple Translation plumbing. Tests that need the model or the
//  Translation framework's language data skip on machines without them
//  (a clean CI runner has no Apple Intelligence).
//

import XCTest
@testable import Reader_for_Language_Learner

@MainActor
final class AppleOnDeviceTests: XCTestCase {

    private func route(_ module: ModuleType?, enabled: Bool = true, available: Bool = true, languages: Bool = true) -> LLMRoute {
        AppleOnDevice.route(for: module, enabled: enabled, modelAvailable: available, languagesSupported: languages)
    }

    // MARK: Routing

    func testReliableModulesGoOnDevice() async {
        for module in [ModuleType.definitionEN, .meaningTR, .examplesEN, .synonymsEN, .usageNotesEN] {
            XCTAssertEqual(route(module), .appleOnDevice, module.rawValue)
        }
        XCTAssertEqual(route(nil), .appleOnDevice, "free-form work (Ask AI, CEFR) runs on-device")
    }

    /// The spike's failures: wrong IPA, invented etymology, nonsense
    /// mnemonics, made-up word forms, shaky collocations.
    func testUnreliableModulesFallBackToTheConfiguredProvider() async {
        for module in [ModuleType.pronunciationEN, .etymologyEN, .mnemonicEN, .wordFamilyEN, .collocations] {
            XCTAssertEqual(route(module), .configured, module.rawValue)
        }
    }

    func testEveryModuleIsClassified() async {
        let fallback: Set<ModuleType> = [.pronunciationEN, .etymologyEN, .mnemonicEN, .wordFamilyEN, .collocations]
        XCTAssertEqual(AppleOnDevice.reliableModules.union(fallback), Set(ModuleType.allCases),
                       "a new module must be placed on one side deliberately")
        XCTAssertTrue(AppleOnDevice.reliableModules.isDisjoint(with: fallback))
    }

    func testAnyMissingPreconditionUsesTheConfiguredProvider() async {
        XCTAssertEqual(route(.definitionEN, enabled: false), .configured)
        XCTAssertEqual(route(.definitionEN, available: false), .configured)
        XCTAssertEqual(route(.definitionEN, languages: false), .configured, "Arabic and Russian aren't supported")
        XCTAssertEqual(route(nil, available: false), .configured)
    }

    // MARK: Live model (skips without Apple Intelligence)

    private func requireModel() throws {
        guard AppleOnDevice.isModelAvailable else { throw XCTSkip("Apple's on-device model isn't available here") }
    }

    func testLanguageSupportMatchesTheSpike() async throws {
        try requireModel()
        for language in [Language.english, .turkish, .german, .french, .spanish, .japanese,
                         .korean, .chinese, .portuguese, .italian] {
            XCTAssertTrue(AppleOnDevice.supports(language), language.rawValue)
        }
        XCTAssertFalse(AppleOnDevice.supports(.arabic))
        XCTAssertFalse(AppleOnDevice.supports(.russian))
    }

    /// Snapshots are cumulative; the client must hand over deltas so the
    /// inspector's `+=` builds the answer once.
    func testStreamingDeliversEachPartOnce() async throws {
        try requireModel()
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else { throw XCTSkip("macOS 26 required") }
        var parts: [String] = []
        _ = try await AppleOnDeviceClient().stream(
            system: "Answer in one short English sentence.",
            user: "What is a cat?",
            temperature: 0.1, maxTokens: 60, topP: 0.9
        ) { parts.append($0) }
        let answer = parts.joined()
        XCTAssertFalse(answer.isEmpty)
        XCTAssertFalse(parts.contains(""), "no empty deltas")
        if let first = parts.first, parts.count > 1, first.count > 8 {
            XCTAssertFalse(answer.dropFirst(first.count).hasPrefix(first), "a snapshot was re-sent whole")
        }
        #else
        throw XCTSkip("FoundationModels not in this SDK")
        #endif
    }

    // MARK: Apple Translation

    func testTranslationLanguageIdentifiers() async {
        XCTAssertEqual(AppleTranslation.localeLanguage(for: .turkish).minimalIdentifier, "tr")
        XCTAssertEqual(AppleTranslation.localeLanguage(for: .chinese).languageCode?.identifier, "zh")
        XCTAssertEqual(AppleTranslation.localeLanguage(for: .chinese).script?.identifier, "Hans")
        XCTAssertEqual(AppleTranslation.localeLanguage(for: .portuguese).region?.identifier, "BR")
    }

    func testSameLanguageIsNeverSentToTranslation() async {
        let canTranslate = await AppleTranslation.canTranslate(from: .english, to: .english)
        XCTAssertFalse(canTranslate)
    }

    func testEngineDefaultsToAppleTranslation() async {
        XCTAssertEqual(SentenceTranslationEngine.default, .apple)
        XCTAssertEqual(SentenceTranslationEngine(rawValue: "aiProvider"), .aiProvider)
    }

    func testAppleTranslationIsCachedForTheStrip() async {
        let service = QuickLookupService()
        let sentence = "Children are remarkably resilient \(UUID().uuidString)."
        XCTAssertNil(service.cachedTranslation(for: sentence))
        service.storeTranslation("Çocuklar dirençlidir.", for: sentence)
        XCTAssertEqual(service.cachedTranslation(for: sentence), "Çocuklar dirençlidir.")
    }
}
