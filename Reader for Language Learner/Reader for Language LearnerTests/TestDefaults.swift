//
//  TestDefaults.swift
//  Reader for Language LearnerTests
//
//  A UserDefaults suite for a test (v18 S0). Removing a suite empties it
//  but leaves its file in ~/Library/Preferences, so a fresh UUID-named
//  suite per test left hundreds of empty files behind. One fixed name per
//  test class, emptied before and after each test, leaves at most one.
//

import XCTest

extension XCTestCase {
    /// An empty defaults suite for this test, emptied again when it ends.
    func scratchDefaults() -> UserDefaults {
        let name = "rell-tests.\(String(describing: type(of: self)))"
        UserDefaults.standard.removePersistentDomain(forName: name)
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: name) }
        return UserDefaults(suiteName: name)!
    }
}
