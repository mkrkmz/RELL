//
//  AnswerFooter.swift
//  Reader for Language Learner
//
//  The line under an answer (Roadmap v17 Sprint 2, approved decisions 1–2):
//  which engine answered, when its first word came and how long the whole
//  answer took — and, when it was slow, why: it waited its turn, the model
//  had to load, or a cloud server was slow to start. Pure.
//

import Foundation

nonisolated struct AnswerFooter: Equatable, Sendable {
    enum Engine: Equatable, Sendable {
        case apple
        case provider(name: String, model: String?)
    }

    enum Flag: Equatable, Sendable {
        /// Waited this long for its turn behind other requests.
        case waited(TimeInterval)
        /// The first word took this long on a model on this Mac with nothing
        /// ahead of it — the model was loading.
        case modelLoaded(TimeInterval)
        /// A cloud server took this long to start answering.
        case slowCloud(TimeInterval)
    }

    let engine: Engine
    let isCached: Bool
    let firstToken: TimeInterval?
    let total: TimeInterval?
    let flag: Flag?

    /// Waiting this long or more is worth saying.
    static let waitWorthTelling: TimeInterval = 1
    /// A local first word slower than this, with no wait, means a load.
    static let loadThreshold: TimeInterval = 5
    /// A cloud first word slower than this is slow.
    static let slowCloudThreshold: TimeInterval = 3

    /// The footer for a finished request; nil while it runs or if it failed
    /// (the error says enough) or was cancelled.
    static func make(_ record: LLMRequestRecord) -> AnswerFooter? {
        guard record.outcome == .finished else { return nil }
        let isApple = record.engine == AppleOnDevice.providerLabel
        let engine: Engine = isApple ? .apple : .provider(name: record.engine, model: record.model)
        let wait = record.wait ?? 0
        let first = record.firstToken ?? 0
        let flag: Flag?
        if wait >= waitWorthTelling {
            flag = .waited(wait)
        } else if record.onThisMac, first > loadThreshold {
            flag = .modelLoaded(first)
        } else if !isApple, !record.onThisMac, first > slowCloudThreshold {
            flag = .slowCloud(first)
        } else {
            flag = nil
        }
        return AnswerFooter(engine: engine, isCached: false, firstToken: record.firstToken,
                            total: record.total, flag: flag)
    }

    /// An answer shown from the saved answers, by the engine that answers
    /// this module now (the cache key holds the provider and model).
    static func cached(engine: Engine) -> AnswerFooter {
        AnswerFooter(engine: engine, isCached: true, firstToken: nil, total: nil, flag: nil)
    }

    /// "0,4 sn" in the reader's locale.
    static func seconds(_ value: TimeInterval) -> String {
        String(localized: "\(value.formatted(.number.precision(.fractionLength(1)))) s")
    }
}
