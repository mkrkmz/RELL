//
//  SpeedSection.swift
//  Reader for Language Learner
//
//  Settings ▸ AI ▸ Speed (Roadmap v17 Sprint 2, approved mockup): a speed
//  test on demand, what to do about it, and the last requests' timings —
//  where an answer comes from and why one was slow, without guessing.
//  Nothing of yours is shown or sent: the test uses a fixed sentence and
//  the list holds no words.
//

import SwiftUI

struct SpeedSection: View {
    static let anchor = "speed"

    private var test: SpeedTest { .shared }
    @State private var showReport = false
    private var log: LLMRequestLog { .shared }

    /// Rows in "Recent requests".
    private static let recentCount = 8

    /// "Why?" under an answer and the status popover open Settings here.
    @MainActor static var revealPending = false

    @MainActor
    static func requestReveal() {
        revealPending = true
        NotificationCenter.default.post(name: .revealSpeedSettings, object: nil)
    }

    var body: some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Speed Test")
                    Text("Sends a short sentence to each engine, one after the other. About 20 seconds.")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                }
                Spacer()
                if case .running(let engine) = test.state {
                    ProgressView().controlSize(.small)
                    Text(engine)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                } else {
                    Button(test.state == .done ? "Run Again" : "Start Test") {
                        Task { await test.run() }
                    }
                }
            }

            if !test.results.isEmpty {
                resultsGrid
            }

            if test.state == .done {
                ForEach(advice) { item in
                    adviceRow(item)
                }
            }

            HStack {
                Text("Describing a problem? The report shows what's set up and how long the last requests took.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
                Spacer()
                Button("Diagnostic Report…") { showReport = true }
            }
            .sheet(isPresented: $showReport) {
                DiagnosticReportSheet { showReport = false }
            }
        } header: {
            Text("Speed")
        } footer: {
            Text("Load: how long the first request took to load the model into memory. The test waits while you ask for something.")
                .foregroundStyle(DS.Color.textTertiary)
        }
        .id(Self.anchor)

        Section {
            let recent = Array(log.records.suffix(Self.recentCount).reversed())
            if recent.isEmpty {
                Text("No requests yet in this session.")
                    .foregroundStyle(DS.Color.textTertiary)
            } else {
                recentGrid(recent)
            }
        } header: {
            Text("Recent Requests")
        } footer: {
            Text("Seconds. The last 200 requests are kept in memory and cleared when RELL quits. No words or sentences are kept.")
                .foregroundStyle(DS.Color.textTertiary)
        }
    }

    // MARK: Results

    private var resultsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: DS.Spacing.md, verticalSpacing: DS.Spacing.xs) {
            GridRow {
                header("Engine"); header("Model"); header("Load").gridColumnAlignment(.trailing)
                header("First Word").gridColumnAlignment(.trailing); header("Speed").gridColumnAlignment(.trailing)
            }
            ForEach(test.results) { result in
                GridRow {
                    Text(result.isApple ? String(localized: "Apple") : result.engine)
                    Text(result.model.map(shortModel) ?? "—")
                        .lineLimit(1).truncationMode(.middle)
                    if let failure = result.failure {
                        Text(failure)
                            .foregroundStyle(DS.Color.warning)
                            .lineLimit(2)
                            .gridCellColumns(3)
                    } else {
                        Text(loadText(result))
                            .foregroundStyle(result.load != nil ? DS.Color.warning : DS.Color.textSecondary)
                        Text(result.firstToken.map(AnswerFooter.seconds) ?? "—")
                        Text(result.wordsPerSecond.map { String(localized: "\(Int($0.rounded())) words/s") } ?? "—")
                            .foregroundStyle(isSlow(result) ? DS.Color.warning : DS.Color.textPrimary)
                    }
                }
                .font(DS.Typography.caption)
                .monospacedDigit()
            }
        }
    }

    private var advice: [SpeedAdvice.Item] {
        let apple: SpeedAdvice.AppleState
        if let reason = AppleOnDevice.unavailableReason {
            apple = .unavailable(reason: reason)
        } else {
            apple = AppleOnDevice.isEnabled ? .on : .offInRELL
        }
        return SpeedAdvice.items(apple: apple, results: test.results,
                                 physicalMemory: ProcessInfo.processInfo.physicalMemory)
    }

    private func adviceRow(_ item: SpeedAdvice.Item) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
            Image(systemName: icon(item.kind))
                .foregroundStyle(color(item.kind))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                Text(item.detail)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Recent

    private func recentGrid(_ records: [LLMRequestRecord]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: DS.Spacing.md, verticalSpacing: DS.Spacing.xs) {
            GridRow {
                header("What"); header("Engine")
                header("Wait").gridColumnAlignment(.trailing); header("First Word").gridColumnAlignment(.trailing)
                header("Total").gridColumnAlignment(.trailing); header("Result")
            }
            ForEach(records) { record in
                GridRow {
                    Text(record.origin.localizedTitle(detail: record.detail)).lineLimit(1)
                    Text(record.engine == AppleOnDevice.providerLabel ? String(localized: "Apple") : record.engine)
                        .lineLimit(1)
                    Text(number(record.wait))
                        .foregroundStyle((record.wait ?? 0) >= AnswerFooter.waitWorthTelling ? DS.Color.warning : DS.Color.textPrimary)
                    Text(number(record.firstToken))
                    Text(number(record.total))
                    Text(record.outcomeTitle)
                        .foregroundStyle(record.outcome == .finished ? DS.Color.textSecondary : DS.Color.warning)
                        .lineLimit(1)
                }
                .font(DS.Typography.caption)
                .monospacedDigit()
            }
        }
    }

    // MARK: Helpers

    private func header(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(DS.Typography.caption2.weight(.semibold))
            .foregroundStyle(DS.Color.textTertiary)
    }

    private func number(_ value: TimeInterval?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—"
    }

    private func shortModel(_ model: String) -> String {
        model.components(separatedBy: "/").last ?? model
    }

    private func loadText(_ result: SpeedTest.Result) -> String {
        if let load = result.load { return AnswerFooter.seconds(load) }
        return result.onThisMac ? String(localized: "was loaded") : "—"
    }

    private func isSlow(_ result: SpeedTest.Result) -> Bool {
        result.onThisMac && (result.wordsPerSecond ?? .infinity) < SpeedAdvice.slowWordsPerSecond
    }

    private func icon(_ kind: SpeedAdvice.Item.Kind) -> String {
        switch kind {
        case .good:    return "checkmark.circle.fill"
        case .info:    return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }

    private func color(_ kind: SpeedAdvice.Item.Kind) -> Color {
        switch kind {
        case .good:    return DS.Color.success
        case .info:    return DS.Color.accent
        case .warning: return DS.Color.warning
        }
    }
}

extension Notification.Name {
    nonisolated static let revealSpeedSettings = Notification.Name("revealSpeedSettings")
}

// MARK: - Names

extension LLMRequestOrigin {
    /// What asked, for the request list. `detail` is the module's raw value.
    func localizedTitle(detail: String?) -> String {
        switch self {
        case .module:
            if let module = detail.flatMap(ModuleType.init(rawValue:)) {
                return module.title(nativeLanguage: Language.storedNative)
            }
            return String(localized: "Inspector")
        case .askAI:       return String(localized: "Ask AI")
        case .quickLookup: return String(localized: "Quick Lookup")
        case .cefr:        return String(localized: "Word level")
        case .fill:        return String(localized: "Fill Missing")
        case .warmUp:      return String(localized: "Chapter warm-up")
        case .recap:       return String(localized: "Recap")
        case .gloss:       return String(localized: "Glosses")
        case .grammar:     return String(localized: "Grammar")
        case .rewrite:     return String(localized: "Simplify")
        case .retell:      return String(localized: "Retell")
        case .story:       return String(localized: "Story")
        case .prewarm:     return String(localized: "Loading the model")
        case .speedTest:   return String(localized: "Speed test")
        }
    }
}

extension LLMRequestRecord {
    var outcomeTitle: String {
        switch outcome {
        case .finished:  return String(localized: "done")
        case .cancelled: return startedAt == nil ? String(localized: "not sent") : String(localized: "stopped")
        case .failed:    return String(localized: "failed")
        case nil:        return startedAt == nil ? String(localized: "waiting") : String(localized: "running")
        }
    }
}
