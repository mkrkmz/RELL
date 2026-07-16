//
//  KeychainHelperTests.swift
//  Reader for Language LearnerTests
//
//  Uses a per-test unique keychain service and always cleans up in the same
//  test — CI runners have flaked historically on shared keychain state.
//

import XCTest
@testable import Reader_for_Language_Learner

final class KeychainHelperTests: XCTestCase {

    private func uniqueService() -> String {
        "com.rell.tests.\(UUID().uuidString)"
    }

    func testWriteReadDeleteRoundTrip() {
        let service = uniqueService()
        defer { KeychainHelper.delete(service: service, account: "k") }

        XCTAssertNil(KeychainHelper.read(service: service, account: "k"))
        XCTAssertTrue(KeychainHelper.write("sk-secret", service: service, account: "k"))
        XCTAssertEqual(KeychainHelper.read(service: service, account: "k"), "sk-secret")

        XCTAssertTrue(KeychainHelper.write("sk-updated", service: service, account: "k"))
        XCTAssertEqual(KeychainHelper.read(service: service, account: "k"), "sk-updated")

        XCTAssertTrue(KeychainHelper.delete(service: service, account: "k"))
        XCTAssertNil(KeychainHelper.read(service: service, account: "k"))
    }

    func testDeleteMissingItemSucceeds() {
        XCTAssertTrue(KeychainHelper.delete(service: uniqueService(), account: "absent"))
    }

    // MARK: - Legacy UserDefaults migration

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "KeychainHelperTests.\(UUID().uuidString)")!
    }

    func testMigrationMovesLegacyKeyAndClearsDefaults() {
        let service = uniqueService()
        let defaults = makeDefaults()
        defer { KeychainHelper.delete(service: service, account: LLMConfiguration.apiKeyKey) }

        defaults.set("sk-legacy", forKey: LLMConfiguration.apiKeyKey)
        LLMConfiguration.migrateLegacyAPIKey(defaults: defaults, service: service)

        XCTAssertEqual(
            KeychainHelper.read(service: service, account: LLMConfiguration.apiKeyKey),
            "sk-legacy"
        )
        XCTAssertNil(defaults.string(forKey: LLMConfiguration.apiKeyKey))
    }

    func testMigrationPrefersExistingKeychainValue() {
        let service = uniqueService()
        let defaults = makeDefaults()
        defer { KeychainHelper.delete(service: service, account: LLMConfiguration.apiKeyKey) }

        KeychainHelper.write("sk-current", service: service, account: LLMConfiguration.apiKeyKey)
        defaults.set("sk-stale-legacy", forKey: LLMConfiguration.apiKeyKey)
        LLMConfiguration.migrateLegacyAPIKey(defaults: defaults, service: service)

        XCTAssertEqual(
            KeychainHelper.read(service: service, account: LLMConfiguration.apiKeyKey),
            "sk-current"
        )
        XCTAssertNil(defaults.string(forKey: LLMConfiguration.apiKeyKey))
    }

    func testMigrationNoOpsWithoutLegacyValue() {
        let service = uniqueService()
        LLMConfiguration.migrateLegacyAPIKey(defaults: makeDefaults(), service: service)
        XCTAssertNil(KeychainHelper.read(service: service, account: LLMConfiguration.apiKeyKey))
    }
}
