//
//  SavedWordDetailSheet+Sentence.swift
//  Reader for Language Learner
//
//  A saved sentence's page, saying it aloud, and the sentences a word is
//  in. Split out of SavedWordDetailSheet.swift (v20 S0), unchanged.
//

import SwiftUI

extension SavedWordDetailSheet {

    /// v19 S3: the saved sentences this word is in — ones you wrote with it
    /// and ones you kept from a book.
    @ViewBuilder
    var yourSentences: some View {
        let sentences = SentenceWords.sentences(containing: word, store: store)
        if !sentences.isEmpty {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text("SENTENCES WITH THIS WORD").dsOverlineLabel()
                ForEach(sentences.prefix(5)) { sentence in
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text(WordPageModel.emphasized(sentence.term, term: word.term, language: language))
                            .font(DS.Typography.callout)
                            .foregroundStyle(DS.Color.textPrimary)
                            .textSelection(.enabled)
                        if let translation = sentence.translation {
                            Text(translation)
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Color.textSecondary)
                        }
                    }
                    .padding(DS.Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.md).strokeBorder(DS.Color.hairline))
                }
            }
        }
    }

    // MARK: - Saying a sentence back (v19 S4)

    /// "Say It Aloud" and the last result: how many words, which were hard.
    @ViewBuilder
    private var spokenRepetitionSection: some View {
        if SpokenRepetitionRecognizer.isOffered(for: language) || current.spokenRepetition != nil {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text("SAYING IT ALOUD").dsOverlineLabel()
                if repeating {
                    SpokenRepetitionView(
                        sentence: word.term,
                        language: language,
                        onResult: { store.recordSpokenRepetition($0, for: word.id) },
                        onClose: { repeating = false }
                    )
                    .padding(DS.Spacing.sm)
                    .background(DS.Color.surfaceInset, in: RoundedRectangle(cornerRadius: DS.Radius.md))
                } else {
                    HStack(spacing: DS.Spacing.sm) {
                        if let record = current.spokenRepetition {
                            Text("Last: \(record.said) of \(record.total) words · \(record.date.formatted(date: .abbreviated, time: .omitted))")
                                .font(DS.Typography.caption.weight(.semibold))
                                .foregroundStyle(record.said == record.total ? DS.Color.success : DS.Color.warning)
                            if !record.hardWords.isEmpty {
                                Text("Hard: \(record.hardWords.joined(separator: ", "))")
                                    .font(DS.Typography.caption)
                                    .foregroundStyle(DS.Color.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: DS.Spacing.sm)
                        if SpokenRepetitionRecognizer.isOffered(for: language) {
                            Button { repeating = true } label: {
                                Label("Say It Aloud", systemImage: "mic")
                            }
                            .buttonStyle(.dsQuiet)
                            .help("Hear the sentence, then say it back")
                        }
                    }
                }
            }
        }
    }

    // MARK: - A saved sentence (v19 S2)

    /// The sentence large, read aloud on request; its translation; the
    /// words in it (saved ones with their status, others one click from
    /// saved); memory; where it's from; details.
    var sentenceSections: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
                Text(SentenceWords.marked(word.term, store: store, language: language))
                    .font(DS.Typography.title)
                    .fontDesign(.serif)
                    .foregroundStyle(DS.Color.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                SpeakButton(text: word.term, size: 15, language: language)
            }

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text("TRANSLATION").dsOverlineLabel()
                if let translation = current.translation {
                    Text(translation)
                        .font(DS.Typography.callout)
                        .foregroundStyle(DS.Color.textSecondary)
                        .textSelection(.enabled)
                } else {
                    HStack(spacing: DS.Spacing.sm) {
                        Text("No translation yet")
                            .font(DS.Typography.callout.italic())
                            .foregroundStyle(DS.Color.textTertiary)
                        Button {
                            translate()
                        } label: {
                            Label(isTranslating ? "Translating…" : "Translate", systemImage: "character.bubble")
                        }
                        .buttonStyle(.dsQuiet)
                        .disabled(quickLookup == nil || isTranslating)
                    }
                }
            }

            spokenRepetitionSection
            sentenceWordsSection
            memoryCard

            if let pdf = word.pdfFilename {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("WHERE YOU SAVED IT").dsOverlineLabel()
                    Text(BookIdentity.displayTitle(pdf) + (word.pageNumber.map { " · \(String(localized: "p. \($0)"))" } ?? ""))
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                }
            }
            detailsSection
        }
    }

    private var sentenceWordsSection: some View {
        let saved = SentenceWords.saved(in: word.term, store: store, language: language)
        let candidates = SentenceWords.candidates(in: word.term, store: store, language: language)
        return VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text("WORDS IN IT").dsOverlineLabel()
            if saved.isEmpty && candidates.isEmpty {
                Text("No other words to save here.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
            }
            ForEach(saved) { savedWord in
                HStack(spacing: DS.Spacing.sm) {
                    Text(savedWord.term).font(DS.Typography.callout.weight(.medium))
                    if let meaning = SavedWordRow.oneLineMeaning(of: savedWord) {
                        Text(MarkdownUtils.sanitizeLLMOutput(meaning))
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Color.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: DS.Spacing.xs)
                    WordStatusBadge(status: WordStatus.of(savedWord))
                }
            }
            ForEach(candidates, id: \.self) { candidate in
                HStack(spacing: DS.Spacing.sm) {
                    Text(candidate).font(DS.Typography.callout)
                    Spacer(minLength: DS.Spacing.xs)
                    Button {
                        saveWord(candidate)
                    } label: {
                        Label("Save", systemImage: "plus")
                    }
                    .buttonStyle(.dsQuiet)
                    .help("Save “\(candidate)” with this sentence")
                }
            }
        }
    }

    /// A word of the sentence, saved with the sentence as its context.
    private func saveWord(_ term: String) {
        store.add(SavedWord(
            term: term,
            sentence: word.term,
            pdfFilename: word.pdfFilename,
            pageNumber: word.pageNumber,
            mode: ExplainMode.word.rawValue,
            language: word.language,
            documentPath: word.documentPath
        ))
    }

    private func translate() {
        guard let quickLookup else { return }
        isTranslating = true
        Task {
            await SentenceTranslation.fill(wordID: word.id, store: store, quickLookup: quickLookup)
            isTranslating = false
        }
    }
}
