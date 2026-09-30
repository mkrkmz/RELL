//
//  MiniEPUB.swift
//  Reader for Language Learner
//
//  Builds a small EPUB 3 from plain text (Roadmap v13 Sprint 4): a web
//  article or a story written from the reader's words becomes a book RELL
//  opens like any other — hover, save, underlines, glosses, warm-up and
//  encounters all work on it.
//

import Foundation

nonisolated enum MiniEPUB {

    struct Chapter {
        var title: String
        var blocks: [ExtractedArticle.Block]
    }

    /// - Parameters:
    ///   - language: BCP-47 code for `dc:language` ("en", "de").
    ///   - note: a closing line under the last chapter — where it came from.
    static func build(
        title: String,
        author: String?,
        language: String,
        chapters: [Chapter],
        note: String? = nil,
        identifier: String = UUID().uuidString
    ) -> Data {
        var entries: [ZIPWriter.Entry] = [
            // Must be first and stored — the EPUB container rule.
            .init(path: "mimetype", data: Data("application/epub+zip".utf8)),
            .init(path: "META-INF/container.xml", data: Data(container.utf8)),
        ]

        var manifest = ""
        var spine = ""
        var navItems = ""
        for (index, chapter) in chapters.enumerated() {
            let file = "chapter\(index + 1).xhtml"
            let isLast = index == chapters.count - 1
            entries.append(.init(
                path: "OEBPS/\(file)",
                data: Data(xhtml(chapter, language: language, note: isLast ? note : nil).utf8)
            ))
            manifest += "    <item id=\"c\(index + 1)\" href=\"\(file)\" media-type=\"application/xhtml+xml\"/>\n"
            spine += "    <itemref idref=\"c\(index + 1)\"/>\n"
            navItems += "      <li><a href=\"\(file)\">\(escape(chapter.title))</a></li>\n"
        }

        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="uid">urn:uuid:\(escape(identifier))</dc:identifier>
            <dc:title>\(escape(title))</dc:title>
            \(author.map { "<dc:creator>\(escape($0))</dc:creator>" } ?? "")
            <dc:language>\(escape(language))</dc:language>
            <meta property="dcterms:modified">\(modified)</meta>
          </metadata>
          <manifest>
            <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
        \(manifest)  </manifest>
          <spine>
        \(spine)  </spine>
        </package>
        """
        let nav = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="\(escape(language))">
          <head><title>\(escape(title))</title></head>
          <body>
            <nav epub:type="toc"><ol>
        \(navItems)    </ol></nav>
          </body>
        </html>
        """
        entries.append(.init(path: "OEBPS/content.opf", data: Data(opf.utf8)))
        entries.append(.init(path: "OEBPS/nav.xhtml", data: Data(nav.utf8)))
        return ZIPWriter.archive(entries)
    }

    private static let container = """
    <?xml version="1.0" encoding="UTF-8"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <rootfiles>
        <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
      </rootfiles>
    </container>
    """

    private static var modified: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date())
    }

    private static func xhtml(_ chapter: Chapter, language: String, note: String?) -> String {
        let body = chapter.blocks.map { block in
            block.isHeading ? "<h2>\(escape(block.text))</h2>" : "<p>\(escape(block.text))</p>"
        }.joined(separator: "\n")
        let footer = note.map { "\n<hr/>\n<p class=\"source\"><small>\(escape($0))</small></p>" } ?? ""
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xml:lang="\(escape(language))">
        <head><title>\(escape(chapter.title))</title></head>
        <body>
        <h1>\(escape(chapter.title))</h1>
        \(body)\(footer)
        </body>
        </html>
        """
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// A file name from a title: letters, digits and dashes, not too long.
    static func fileName(for title: String) -> String {
        let slug = title.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
            .joined()
            .split(separator: "-")
            .joined(separator: "-")
        let trimmed = String(slug.prefix(60))
        return (trimmed.isEmpty ? "untitled" : trimmed) + ".epub"
    }
}
