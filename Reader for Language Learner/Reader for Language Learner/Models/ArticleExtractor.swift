//
//  ArticleExtractor.swift
//  Reader for Language Learner
//
//  Pulls the readable text out of a web article (Roadmap v13 Sprint 4): the
//  title and the body paragraphs, without menus, ads, captions or scripts.
//  A small readability heuristic over the system's HTML parser — no
//  dependencies. Pure and `nonisolated`; the caller fetches the page.
//

import Foundation

nonisolated struct ExtractedArticle: Equatable, Sendable {
    var title: String
    /// Site name or byline, when the page declares one.
    var source: String?
    /// Body text in reading order: paragraphs and the section headings
    /// between them (`isHeading`).
    var blocks: [Block]

    struct Block: Equatable, Sendable {
        let text: String
        let isHeading: Bool
    }

    var wordCount: Int {
        blocks.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
    }
}

nonisolated enum ArticleExtractor {

    enum Failure: Error, Equatable {
        case notHTML
        case noArticleText
    }

    /// Fewer words than this isn't an article — a paywall stub, an index page.
    static let minimumWords = 120
    /// Paragraph shorter than this is chrome ("Share", "Advertisement").
    static let minimumParagraphLength = 25

    /// Elements whose text never belongs to the article body.
    static let strippedElements: Set<String> = [
        "script", "style", "noscript", "nav", "header", "footer", "aside", "form",
        "button", "iframe", "svg", "figure", "figcaption", "template", "select", "dialog",
    ]

    /// Lines that are site furniture even inside the body container.
    static let boilerplatePrefixes = [
        "advertisement", "sign up", "subscribe", "read more", "related:", "share this",
        "follow us", "all rights reserved", "copyright", "©", "image:", "photo:",
        "listen to this article", "click here",
    ]

    /// - Parameter declaredCharset: the HTTP `Content-Type` charset, if any.
    static func extract(html data: Data, url: URL? = nil, declaredCharset: String? = nil) throws -> ExtractedArticle {
        // Decoded here, not by the parser: given bytes, tidy fell back to
        // Latin-1 on pages that say UTF-8 only in a <meta>, and every curly
        // quote came out as "â€™".
        guard let html = decode(data, declaredCharset: declaredCharset),
              let document = try? XMLDocument(xmlString: html, options: [.documentTidyHTML]),
              let root = document.rootElement()
        else { throw Failure.notHTML }

        let title = metaContent(root, property: "og:title")
            ?? firstText(root, xpath: "//*[local-name()='title']").map(cleanTitle)
            ?? url?.host ?? ""
        let source = metaContent(root, property: "og:site_name")
            ?? metaContent(root, name: "author")
            ?? url?.host

        strip(root)
        var blocks = paragraphBlocks(root)
        // Older hand-written pages (essays, personal sites) have no <p> at
        // all — paragraphs are runs of text between <br><br>.
        if blocks.reduce(0, { $0 + $1.text.split(separator: " ").count }) < minimumWords {
            blocks = lineBreakBlocks(root)
        }

        let article = ExtractedArticle(title: normalize(title), source: source.map(normalize), blocks: blocks)
        guard article.wordCount >= minimumWords else { throw Failure.noArticleText }
        return article
    }

    private static func paragraphBlocks(_ root: XMLElement) -> [ExtractedArticle.Block] {
        guard let body = bestContainer(root) else { return [] }
        var blocks: [ExtractedArticle.Block] = []
        var seen: Set<String> = []
        for node in (try? body.nodes(forXPath: ".//*[local-name()='p' or local-name()='h2' or local-name()='h3' or local-name()='blockquote' or local-name()='li']")) ?? [] {
            guard let element = node as? XMLElement, let name = element.localName?.lowercased() else { continue }
            // A <p> inside a <blockquote>/<li> would otherwise be counted twice.
            if name != "p", containsParagraph(element) { continue }
            if name == "li", !isInsideProse(element) { continue }
            let text = normalize(element.stringValue ?? "")
            let isHeading = name == "h2" || name == "h3"
            guard isHeading ? text.count >= 3 : isParagraph(text) && !isMostlyLinks(element) else { continue }
            guard seen.insert(text).inserted else { continue }
            blocks.append(.init(text: text, isHeading: isHeading))
        }
        // A heading with nothing after it is a trailing "More stories" label.
        while let last = blocks.last, last.isHeading { blocks.removeLast() }
        return blocks
    }

    /// The element with the most text directly inside it (not in child
    /// blocks), split into paragraphs at every double line break.
    static func lineBreakBlocks(_ root: XMLElement) -> [ExtractedArticle.Block] {
        let inline: Set<String> = ["a", "b", "i", "em", "strong", "span", "font", "u", "sup", "sub", "small", "q", "cite"]
        func directText(_ element: XMLElement) -> Int {
            (element.children ?? []).reduce(0) { total, child in
                if child.kind == .text { return total + normalize(child.stringValue ?? "").count }
                // An inline element that itself holds <br>s (a <font> wrapping
                // the whole essay) is the container, not text of its parent.
                if let e = child as? XMLElement, inline.contains(e.localName?.lowercased() ?? ""),
                   ((try? e.nodes(forXPath: ".//*[local-name()='br']")) ?? []).isEmpty {
                    return total + normalize(e.stringValue ?? "").count
                }
                return total
            }
        }
        let all = ((try? root.nodes(forXPath: "//*")) ?? []).compactMap { $0 as? XMLElement }
        func breaks(_ element: XMLElement) -> Int {
            (element.children ?? []).filter { ($0 as? XMLElement)?.localName?.lowercased() == "br" }.count
        }
        // A <td> holding one <font> scores the same as the <font>; the one
        // that actually holds the <br>s is the one to split.
        guard let container = all.max(by: {
            (directText($0), breaks($0)) < (directText($1), breaks($1))
        }) else { return [] }

        var paragraphs: [String] = []
        var current = ""
        var pendingBreak = false
        func flush() {
            let text = normalize(current)
            if isParagraph(text) { paragraphs.append(text) }
            current = ""
        }
        for child in container.children ?? [] {
            if let element = child as? XMLElement, element.localName?.lowercased() == "br" {
                if pendingBreak { flush(); pendingBreak = false } else { pendingBreak = true }
                continue
            }
            let text = child.stringValue ?? ""
            if child.kind == .text, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            if pendingBreak { current += " " }
            pendingBreak = false
            current += text
        }
        flush()
        return paragraphs.map { .init(text: $0, isHeading: false) }
    }

    // MARK: - Container

    /// The element that holds the article. Readability's scoring: every
    /// paragraph adds its length to its parent and half to its grandparent,
    /// so a body whose paragraphs are each wrapped in their own `<div>` (BBC)
    /// still collects them all one level up. An `<article>` or `<main>` that
    /// holds real text wins outright.
    static func bestContainer(_ root: XMLElement) -> XMLElement? {
        for tag in ["article", "main"] {
            let candidates = ((try? root.nodes(forXPath: "//*[local-name()='\(tag)']")) ?? [])
                .compactMap { $0 as? XMLElement }
            if let best = candidates.max(by: { proseLength($0) < proseLength($1) }),
               proseLength(best) >= minimumWords * 5 {
                return best
            }
        }

        var scores: [ObjectIdentifier: (element: XMLElement, score: Double)] = [:]
        func add(_ element: XMLElement?, _ amount: Double) {
            guard let element else { return }
            let key = ObjectIdentifier(element)
            scores[key] = (element, (scores[key]?.score ?? 0) + amount)
        }
        for node in (try? root.nodes(forXPath: "//*[local-name()='p']")) ?? [] {
            guard let element = node as? XMLElement else { continue }
            let text = normalize(element.stringValue ?? "")
            guard isParagraph(text), !isMostlyLinks(element) else { continue }
            // Three levels, decaying: bodies wrap each paragraph in one or
            // two layers of <div> (BBC, DW), and the article sits above them.
            var ancestor = element.parent as? XMLElement
            for divisor in [1.0, 2.0, 3.0] {
                add(ancestor, Double(text.count) / divisor)
                ancestor = ancestor?.parent as? XMLElement
            }
        }
        return scores.values.max { $0.score < $1.score }?.element
    }

    private static func proseLength(_ element: XMLElement) -> Int {
        ((try? element.nodes(forXPath: ".//*[local-name()='p']")) ?? [])
            .map { normalize($0.stringValue ?? "") }
            .filter(isParagraph)
            .reduce(0) { $0 + $1.count }
    }

    /// Child elements by local name, namespace ignored — tidied HTML comes
    /// back in the XHTML namespace, which `elements(forLocalName:uri: nil)`
    /// doesn't match.
    static func children(_ element: XMLElement, named name: String) -> [XMLElement] {
        (element.children ?? []).compactMap { $0 as? XMLElement }.filter { $0.localName?.lowercased() == name }
    }

    private static func containsParagraph(_ element: XMLElement) -> Bool {
        !(((try? element.nodes(forXPath: ".//*[local-name()='p']")) ?? []).isEmpty)
    }

    /// List items count as body text only in a list that sits among prose,
    /// not in a menu of links.
    private static func isInsideProse(_ element: XMLElement) -> Bool {
        let text = normalize(element.stringValue ?? "")
        return text.split(separator: " ").count >= 6
    }

    // MARK: - Cleaning

    private static func strip(_ root: XMLElement) {
        let xpath = strippedElements.map { "//*[local-name()='\($0)']" }.joined(separator: " | ")
        for node in (try? root.nodes(forXPath: xpath)) ?? [] {
            node.detach()
        }
        // Hidden elements and ARIA-hidden furniture.
        for node in (try? root.nodes(forXPath: "//*[@hidden or @aria-hidden='true']")) ?? [] {
            node.detach()
        }
    }

    /// A "paragraph" that is mostly link text is navigation ("Back to the
    /// home page", "Read also: …"), not prose — readability's link density.
    static func isMostlyLinks(_ element: XMLElement) -> Bool {
        let total = normalize(element.stringValue ?? "").count
        guard total > 0 else { return true }
        let linked = ((try? element.nodes(forXPath: ".//*[local-name()='a']")) ?? [])
            .reduce(0) { $0 + normalize($1.stringValue ?? "").count }
        return Double(linked) / Double(total) > 0.5
    }

    /// Bytes to text: the HTTP charset, else a `<meta charset>` in the first
    /// few kilobytes, else UTF-8, else Latin-1 (which never fails).
    static func decode(_ data: Data, declaredCharset: String?) -> String? {
        var names: [String] = []
        if let declaredCharset { names.append(declaredCharset) }
        let head = String(decoding: data.prefix(4096), as: UTF8.self).lowercased()
        if let range = head.range(of: #"charset=["']?([a-z0-9_\-]+)"#, options: .regularExpression) {
            let match = head[range].replacingOccurrences(of: "charset=", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            names.append(match)
        }
        names.append("utf-8")
        for name in names {
            let encoding = CFStringConvertEncodingToNSStringEncoding(
                CFStringConvertIANACharSetNameToEncoding(name as CFString)
            )
            guard encoding != UInt(kCFStringEncodingInvalidId),
                  let text = String(data: data, encoding: String.Encoding(rawValue: encoding))
            else { continue }
            return text
        }
        return String(data: data, encoding: .isoLatin1)
    }

    static func isParagraph(_ text: String) -> Bool {
        guard text.count >= minimumParagraphLength, !isDoubled(text) else { return false }
        let lower = text.lowercased()
        return !boilerplatePrefixes.contains { lower.hasPrefix($0) }
    }

    /// "Back to home page Le MondeBack to home page Le Monde" — a visually
    /// hidden label next to its visible twin, read as one run of text.
    static func isDoubled(_ text: String) -> Bool {
        guard text.count % 2 == 0 else { return false }
        return text.prefix(text.count / 2) == text.suffix(text.count / 2)
    }

    static func normalize(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// "Headline | Site Name" → "Headline".
    static func cleanTitle(_ raw: String) -> String {
        let separators = [" | ", " — ", " – ", " - "]
        for separator in separators {
            if let range = raw.range(of: separator, options: .backwards) {
                let head = String(raw[..<range.lowerBound])
                if head.count >= 12 { return head }
            }
        }
        return raw
    }

    private static func metaContent(_ root: XMLElement, property: String) -> String? {
        firstAttribute(root, xpath: "//*[local-name()='meta'][@property='\(property)']/@content")
    }

    private static func metaContent(_ root: XMLElement, name: String) -> String? {
        firstAttribute(root, xpath: "//*[local-name()='meta'][@name='\(name)']/@content")
    }

    private static func firstAttribute(_ root: XMLElement, xpath: String) -> String? {
        guard let value = (try? root.nodes(forXPath: xpath))?.first?.stringValue else { return nil }
        let text = normalize(value)
        return text.isEmpty ? nil : text
    }

    private static func firstText(_ root: XMLElement, xpath: String) -> String? {
        firstAttribute(root, xpath: xpath)
    }
}
