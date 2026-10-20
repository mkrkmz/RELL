//
//  SpokenRepetition.swift
//  Reader for Language Learner
//
//  "Say it back" (Roadmap v19 Sprint 4, approved mockup): the sentence is
//  read aloud, the reader repeats it, and what the Mac heard — recognised
//  on this Mac, never recorded or sent — is set against the sentence word
//  by word: said, missed, heard as something else. Case, punctuation and
//  how a number is written don't count as differences. Practice only.
//

import Foundation

nonisolated enum SpokenRepetition {

    enum Kind: Equatable, Sendable {
        case said
        case missed
        /// Heard as another word (or words).
        case different(heard: String)
    }

    struct Word: Equatable, Sendable {
        /// As written in the sentence, punctuation included.
        let text: String
        let kind: Kind
    }

    struct Result: Equatable, Sendable {
        let words: [Word]
        var said: Int { words.filter { $0.kind == .said }.count }
        var total: Int { words.count }
        var isPerfect: Bool { total > 0 && said == total }
        /// Words missed or heard as something else, without punctuation.
        var hardWords: [String] {
            words.filter { $0.kind != .said }.map { SpokenRepetition.bare($0.text) }.filter { !$0.isEmpty }
        }
    }

    /// Selections shorter than this aren't offered — recognition of a single
    /// word misleads too often (approved decision 3).
    static let minimumWords = 3
    /// Listening stops after this much silence once speech has begun…
    static let silenceAfterSpeech: TimeInterval = 1.5
    /// …after this long with nothing heard at all…
    static let silenceBeforeSpeech: TimeInterval = 6
    /// …and in any case after this.
    static let maximumListening: TimeInterval = 20

    /// Whether the microphone shows: switched on, recognisable on this Mac,
    /// and not refused (approved: hidden otherwise, the reason in Settings).
    static func offers(enabled: Bool, availability: SpokenRepetitionRecognizer.Availability,
                       access: SpokenRepetitionRecognizer.Access) -> Bool {
        enabled && availability == .ready && access != .denied
    }

    static func isEligible(_ text: String) -> Bool {
        text.split(whereSeparator: \.isWhitespace).count >= minimumWords
    }

    // MARK: Comparing

    /// `heard` set against `sentence`, word by word.
    ///
    /// Longest common subsequence over normalised words; between two
    /// matches, the sentence's unmatched words pair up in order with what
    /// was heard there ("different"), and those left over were missed.
    /// Extra words heard are dropped — they aren't in the sentence.
    static func compare(sentence: String, heard: String) -> Result {
        let written = sentence.split(whereSeparator: \.isWhitespace).map(String.init)
        let expected = written.map(normalized)
        let spoken = heard.split(whereSeparator: \.isWhitespace).map(String.init).map(normalized).filter { !$0.isEmpty }
        let n = expected.count, m = spoken.count

        var lcs = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        if n > 0, m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    lcs[i][j] = matches(expected[i], spoken[j]) ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
                }
            }
        }

        var words: [Word] = []
        var pendingWritten: [Int] = []
        var pendingHeard: [String] = []

        func flush() {
            for (offset, index) in pendingWritten.enumerated() {
                if offset < pendingHeard.count {
                    // The last unmatched written word takes whatever heard words remain.
                    let heard = offset == pendingWritten.count - 1
                        ? pendingHeard[offset...].joined(separator: " ")
                        : pendingHeard[offset]
                    words.append(Word(text: written[index], kind: .different(heard: heard)))
                } else {
                    words.append(Word(text: written[index], kind: .missed))
                }
            }
            pendingWritten = []
            pendingHeard = []
        }

        var i = 0, j = 0
        while i < n || j < m {
            if i < n, expected[i].isEmpty {
                // A dash or a lone mark: nothing to say, counted as said.
                words.append(Word(text: written[i], kind: .said)); i += 1
            } else if i < n, j < m, matches(expected[i], spoken[j]) {
                flush()
                words.append(Word(text: written[i], kind: .said)); i += 1; j += 1
            } else if j < m, i == n || lcs[i][j + 1] >= lcs[i + 1][j] {
                pendingHeard.append(spoken[j]); j += 1
            } else {
                pendingWritten.append(i); i += 1
            }
        }
        flush()
        // A heard word left over after the last written one isn't pairable.
        return Result(words: words)
    }

    /// Two normalised words count as the same: equal, or — five letters
    /// and up — one letter apart (colour / color, harbour / harbor).
    static func matches(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        guard min(a.count, b.count) >= 5, abs(a.count - b.count) <= 1 else { return false }
        return editDistance(a, b) <= 1
    }

    /// Lower case, no punctuation; spelled-out numbers as digits.
    static func normalized(_ word: String) -> String {
        let bare = bare(word).lowercased()
        return numberWords[bare].map(String.init) ?? bare
    }

    /// The word without the punctuation around it ("again." → "again"),
    /// keeping inner apostrophes ("didn't").
    static func bare(_ word: String) -> String {
        word.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.symbols).union(.whitespaces))
            .replacingOccurrences(of: "’", with: "'")
    }

    /// English and Turkish number words — the recogniser writes "11" for
    /// "eleven", and a book may write either.
    static let numberWords: [String: Int] = {
        var map: [String: Int] = [:]
        let english = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
                       "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen",
                       "nineteen", "twenty"]
        for (value, word) in english.enumerated() { map[word] = value }
        for (word, value) in [("thirty", 30), ("forty", 40), ("fifty", 50), ("sixty", 60), ("seventy", 70),
                              ("eighty", 80), ("ninety", 90), ("hundred", 100), ("thousand", 1000)] {
            map[word] = value
        }
        let turkish = ["sıfır", "bir", "iki", "üç", "dört", "beş", "altı", "yedi", "sekiz", "dokuz", "on"]
        for (value, word) in turkish.enumerated() { map[word] = value }
        for (word, value) in [("yirmi", 20), ("otuz", 30), ("kırk", 40), ("elli", 50), ("altmış", 60),
                              ("yetmiş", 70), ("seksen", 80), ("doksan", 90), ("yüz", 100), ("bin", 1000)] {
            map[word] = value
        }
        return map
    }()

    private static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = a[i - 1] == b[j - 1] ? previous[j - 1] : 1 + min(previous[j - 1], previous[j], current[j - 1])
            }
            previous = current
        }
        return previous[b.count]
    }

    // MARK: The last result, kept on a saved sentence

    /// What a saved sentence keeps of its last repetition: counts and the
    /// hard words — never the sound, never the text heard.
    struct Record: Codable, Equatable, Sendable {
        let said: Int
        let total: Int
        let hardWords: [String]
        let date: Date

        init(_ result: Result, date: Date = Date()) {
            said = result.said
            total = result.total
            hardWords = Array(result.hardWords.prefix(8))
            self.date = date
        }

        var encoded: String? {
            (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) }
        }

        static func decoded(_ text: String?) -> Record? {
            text.flatMap { $0.data(using: .utf8) }.flatMap { try? JSONDecoder().decode(Record.self, from: $0) }
        }
    }

    /// Where a saved sentence keeps its record (next to its translation).
    static let recordKey = "spokenRepetition"
}

extension SavedWordsStore {
    /// Keeps the last repetition on a saved sentence — counts and hard words.
    func recordSpokenRepetition(_ result: SpokenRepetition.Result, for id: UUID, date: Date = Date()) {
        guard var word = word(withID: id), word.isSentence,
              let encoded = SpokenRepetition.Record(result, date: date).encoded else { return }
        word.llmOutputs[SpokenRepetition.recordKey] = encoded
        update(word)
    }

    /// The saved sentence card with exactly this text, if there is one.
    func savedSentence(matching text: String) -> SavedWord? {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return sentences.first { $0.term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == key }
    }
}

extension SavedWord {
    /// The last spoken repetition of a saved sentence (v19 S4).
    var spokenRepetition: SpokenRepetition.Record? {
        SpokenRepetition.Record.decoded(llmOutputs[SpokenRepetition.recordKey])
    }
}
