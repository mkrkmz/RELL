//
//  UpdateChecker.swift
//  Reader for Language Learner
//
//  Is there a newer RELL? (Roadmap v17 Sprint 3, approved decision 3.) At
//  most once a day, at launch, RELL asks GitHub for the latest release's
//  version and notes — nothing is sent but the request itself. A newer one
//  shows a banner on the home screen; Download opens its page in the browser.
//  RELL never downloads or installs anything itself. Off in Settings ▸ Data;
//  never on a local build (version 1.0) or in the test host.
//

import Foundation

@MainActor
@Observable
final class UpdateChecker {
    /// Off the main actor: on macOS 15 a main-actor deinit run outside a
    /// task crashes when it releases another one (v16 S0, CI crash reports).
    nonisolated deinit {}

    static let shared = UpdateChecker()

    nonisolated static let latestReleaseURL = URL(string: "https://api.github.com/repos/mkrkmz/RELL/releases/latest")!
    nonisolated static let releasesPageURL = URL(string: "https://github.com/mkrkmz/RELL/releases/latest")!
    nonisolated static let interval: TimeInterval = 24 * 60 * 60

    nonisolated struct Release: Equatable, Sendable {
        let version: String
        let pageURL: URL
        /// The release notes (the CHANGELOG section), Markdown.
        let notes: String
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case failed(String)
    }

    private(set) var state: State = .idle

    var appVersion: String { WhatsNew.appVersion }

    /// The release to tell about on the home screen, unless hidden.
    var bannerRelease: Release? {
        guard case .available(let release) = state,
              UserDefaults.standard.string(forKey: StorageKey.updateHiddenVersion) != release.version
        else { return nil }
        return release
    }

    func hideBanner(for release: Release) {
        UserDefaults.standard.set(release.version, forKey: StorageKey.updateHiddenVersion)
        state = .available(release)   // re-render the banner away
    }

    /// At launch: when on, a release build, and a day has passed.
    func checkIfDue(now: Date = Date()) {
        let defaults = UserDefaults.standard
        guard !RELLProcess.isTestHost,
              defaults.object(forKey: StorageKey.updateCheckEnabled) as? Bool ?? true,
              Self.isReleaseBuild(appVersion),
              Self.isDue(lastCheck: defaults.object(forKey: StorageKey.updateLastCheck) as? Date, now: now)
        else { return }
        Task { await check() }
    }

    /// Asks GitHub now (Help ▸ Check for Updates…, Settings).
    func check(now: Date = Date()) async {
        guard state != .checking else { return }
        state = .checking
        var request = URLRequest(url: Self.latestReleaseURL, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, let release = Self.release(from: data) else {
                state = .failed(String(localized: "GitHub didn't answer as expected. Try again later."))
                return
            }
            UserDefaults.standard.set(now, forKey: StorageKey.updateLastCheck)
            state = Self.isNewer(release.version, than: appVersion) ? .available(release) : .upToDate
        } catch {
            state = .failed(LLMErrorMessage.userMessage(for: error))
        }
    }

    var lastCheck: Date? {
        UserDefaults.standard.object(forKey: StorageKey.updateLastCheck) as? Date
    }

    // MARK: Pure

    /// A build from the release workflow: Xcode's own builds say 1.0.
    nonisolated static func isReleaseBuild(_ version: String) -> Bool {
        let parts = numbers(version)
        return !parts.isEmpty && parts != [1, 0] && parts != [1]
    }

    nonisolated static func isDue(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= interval
    }

    /// "v1.47.0" > "1.46.1"; missing parts count as 0.
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = numbers(candidate), b = numbers(current)
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    nonisolated static func numbers(_ version: String) -> [Int] {
        let trimmed = version.trimmingCharacters(in: .whitespaces)
        let bare = trimmed.hasPrefix("v") || trimmed.hasPrefix("V") ? String(trimmed.dropFirst()) : trimmed
        return bare.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }

    /// GitHub's latest-release answer; drafts and pre-releases don't count.
    nonisolated static func release(from data: Data) -> Release? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = object["tag_name"] as? String,
              (object["draft"] as? Bool) != true, (object["prerelease"] as? Bool) != true
        else { return nil }
        let page = (object["html_url"] as? String).flatMap(URL.init(string:)) ?? releasesPageURL
        let version = numbers(tag).map(String.init).joined(separator: ".")
        return Release(version: version, pageURL: page, notes: object["body"] as? String ?? "")
    }
}
