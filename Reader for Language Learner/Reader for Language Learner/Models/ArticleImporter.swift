//
//  ArticleImporter.swift
//  Reader for Language Learner
//
//  Web article → local book (Roadmap v13 Sprint 4). Fetches the page the
//  reader pasted, keeps the readable text (`ArticleExtractor`), and saves it
//  as a small EPUB under Application Support/RELL/Articles, where it opens
//  like any other book. Only the page itself is fetched — no images, no
//  scripts; nothing is sent to the AI.
//

import Foundation
import NaturalLanguage

enum ArticleImporter {

    enum ImportError: LocalizedError, Equatable {
        case notAWebAddress
        case unreachable(String)
        case notAPage
        case noArticle

        var errorDescription: String? {
            switch self {
            case .notAWebAddress:
                return String(localized: "That doesn't look like a web address. Paste a link that starts with http:// or https://.")
            case .unreachable(let reason):
                return String(localized: "Couldn't load the page: \(reason)")
            case .notAPage:
                return String(localized: "That link isn't a web page.")
            case .noArticle:
                return String(localized: "No article text found on that page. It may be behind a paywall, or built by scripts RELL doesn't run.")
            }
        }
    }

    static let folderName = "Articles"

    /// A pasted address, with `https://` added when the scheme was left off.
    nonisolated static func webURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: withScheme),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, host.contains(".")
        else { return nil }
        return url
    }

    /// Fetches, extracts and saves; returns the new book's file URL.
    static func importArticle(from url: URL, session: URLSession = .shared) async throws -> URL {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ImportError.unreachable(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ImportError.unreachable(HTTPURLResponse.localizedString(forStatusCode: http.statusCode))
        }
        if let mime = response.mimeType, !mime.contains("html") { throw ImportError.notAPage }

        let article: ExtractedArticle
        do {
            article = try ArticleExtractor.extract(
                html: data, url: response.url ?? url, declaredCharset: response.textEncodingName
            )
        } catch {
            throw ImportError.noArticle
        }
        return try save(article, from: response.url ?? url)
    }

    static func save(_ article: ExtractedArticle, from url: URL, now: Date = Date()) throws -> URL {
        let folder = try articlesFolder()
        let date = now.formatted(date: .abbreviated, time: .omitted)
        let book = MiniEPUB.build(
            title: article.title,
            author: article.source,
            language: languageCode(of: article),
            chapters: [.init(title: article.title, blocks: article.blocks)],
            note: String(localized: "From \(url.absoluteString), \(date).")
        )
        let destination = uniqueFile(named: MiniEPUB.fileName(for: article.title), in: folder)
        try book.write(to: destination, options: .atomic)
        return destination
    }

    static func articlesFolder() throws -> URL {
        guard let base = FileManager.default.rellAppSupportDirectory() else {
            throw CocoaError(.fileNoSuchFile)
        }
        let folder = base.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// "title.epub", then "title-2.epub" … — importing the same page twice
    /// keeps both rather than replacing a book that may carry highlights.
    static func uniqueFile(named name: String, in folder: URL) -> URL {
        let base = (name as NSString).deletingPathExtension
        var candidate = folder.appendingPathComponent(name)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base)-\(number).epub")
            number += 1
        }
        return candidate
    }

    nonisolated static func languageCode(of article: ExtractedArticle) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(article.blocks.prefix(8).map(\.text).joined(separator: " "))
        return recognizer.dominantLanguage?.rawValue ?? "en"
    }
}
