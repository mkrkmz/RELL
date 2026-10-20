//
//  SentenceWriting.swift
//  Reader for Language Learner
//
//  "Write a sentence with it" (Roadmap v19 Sprint 3): the learner uses a
//  saved word in a sentence of their own; the model corrects it, says why
//  in the learner's language and gives a natural example in the sense the
//  word was saved in. Practice only — nothing reaches the review schedule.
//

import Foundation

/// A reply made of labelled parts ("VERDICT: …", "WHY: …"). A label starts
/// a line; the text after it, and on the lines that follow, is its part.
/// Markdown bold and list marks around a label are ignored — models add them.
nonisolated enum LabelledReply {

    static func sections(_ raw: String, labels: [String]) -> [String: String] {
        var result: [String: String] = [:]
        var current: String?
        var buffer: [String] = []

        func close() {
            guard let current else { return }
            let text = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if result[current] == nil || result[current]!.isEmpty { result[current] = text }
        }

        for rawLine in raw.components(separatedBy: .newlines) {
            let line = rawLine.replacingOccurrences(of: "**", with: "")
                .trimmingCharacters(in: .whitespaces)
            let bare = line.drop { $0 == "-" || $0 == "*" || $0 == "#" || $0 == " " }
            if let label = labels.first(where: { bare.uppercased().hasPrefix($0) }) {
                close()
                current = label
                buffer = [String(bare.dropFirst(label.count)).trimmingCharacters(in: .whitespaces)]
            } else if current != nil {
                buffer.append(line)
            }
        }
        close()
        return result
    }
}

nonisolated enum SentenceWriting {

    enum Verdict: String, Equatable, Sendable {
        /// Right first time — nothing to fix.
        case natural
        /// Grammar, spelling or word choice fixed.
        case fixed
        /// The word is used, but not in the sense it was saved in.
        case otherSense
    }

    struct Feedback: Equatable, Sendable {
        let verdict: Verdict
        let corrected: String
        let why: String
        let example: String
        /// The kind of fix in a few words, in the learner's language — for
        /// the session summary's "most common fix". Nil when natural.
        let topic: String?
    }

    /// Thinking models spend tokens before answering (v13 spike).
    static let maxTokens = 900
    /// Fewer words than this isn't a sentence worth checking.
    static let minimumWords = 3
    /// Session sizes offered in the study room's setup (approved: 5).
    static let sizeChoices = [3, 5, 10]
    static let defaultSize = 5

    /// Parser-bound labels — English and fixed, whatever the languages.
    static let verdictLabel = "VERDICT:"
    static let correctedLabel = "CORRECTED:"
    static let whyLabel = "WHY:"
    static let exampleLabel = "EXAMPLE:"
    static let topicLabel = "TOPIC:"

    static func isWorthChecking(_ sentence: String) -> Bool {
        sentence.split(whereSeparator: \.isWhitespace).count >= minimumWords
    }

    static func systemPrompt(target: Language, native: Language, level: CEFRLevel) -> String {
        """
        You are a kind \(target.rawValue) teacher. A CEFR \(level.rawValue) learner wrote \
        one sentence using a WORD they are learning, in the SENSE given. Correct the \
        sentence: fix grammar, spelling and word choice, but keep the learner's own \
        words and idea wherever they work. Then judge it:
        - NATURAL: correct and natural as written;
        - FIXED: you changed something;
        - OTHER SENSE: the word is used, but not in the given sense.
        Reply in exactly this format:
        \(verdictLabel) NATURAL, FIXED or OTHER SENSE
        \(correctedLabel) <the corrected sentence>
        \(whyLabel) <one or two short sentences in \(native.rawValue): what you fixed and why, \
        and whether the word is used in the given sense>
        \(exampleLabel) <one natural \(target.rawValue) sentence of your own using the word in that sense, \
        at the learner's level>
        \(topicLabel) <the kind of fix in two to four \(native.rawValue) words, or NONE>
        """
    }

    static func userPrompt(word: String, sense: String?, bookSentence: String?, sentence: String) -> String {
        var lines = ["WORD: \(word)"]
        if let sense, !sense.isEmpty { lines.append("SENSE: \(sense)") }
        if let bookSentence, !bookSentence.isEmpty { lines.append("WHERE THE LEARNER MET IT: \(bookSentence)") }
        lines.append("LEARNER'S SENTENCE: \(sentence)")
        return lines.joined(separator: "\n")
    }

    /// Reads the labelled reply; nil without a corrected sentence and a
    /// reason. The verdict is checked against what actually changed: a
    /// "natural" sentence the model still edited counts as fixed, a "fixed"
    /// one it left word for word counts as natural.
    static func parse(_ raw: String, written: String) -> Feedback? {
        let parts = LabelledReply.sections(raw, labels: [verdictLabel, correctedLabel, whyLabel, exampleLabel, topicLabel])
        let corrected = unquoted(parts[correctedLabel] ?? "")
        guard let why = parts[whyLabel], !why.isEmpty, !corrected.isEmpty else { return nil }

        let said = (parts[verdictLabel] ?? "").uppercased().filter(\.isLetter)
        let changed = WordDiff.diff(written, corrected).contains { $0.kind != .same }
        let verdict: Verdict
        if said.hasPrefix("OTHER") {
            verdict = .otherSense
        } else {
            verdict = changed ? .fixed : .natural
        }
        let topic = parts[topicLabel].map(unquoted).flatMap { text -> String? in
            let cleaned = text.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
            return cleaned.isEmpty || cleaned.uppercased() == "NONE" || verdict == .natural ? nil : cleaned
        }
        return Feedback(verdict: verdict, corrected: corrected, why: why,
                        example: unquoted(parts[exampleLabel] ?? ""), topic: topic)
    }

    /// The fix that came up most, when it came up more than once.
    static func commonestTopic(_ feedbacks: [Feedback]) -> (topic: String, count: Int)? {
        var counts: [String: (topic: String, count: Int)] = [:]
        for topic in feedbacks.compactMap(\.topic) {
            let key = topic.lowercased()
            counts[key, default: (topic, 0)].count += 1
        }
        return counts.values.filter { $0.count >= 2 }.max { $0.count < $1.count }
    }

    private static func unquoted(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”«»'"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
