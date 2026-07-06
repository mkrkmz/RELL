//
//  EPUBDocument.swift
//  Reader for Language Learner
//
//  Parses an EPUB (2 or 3) from a ZIPArchive: container.xml → OPF package
//  (metadata, manifest, spine) → table of contents (EPUB3 nav.xhtml with an
//  EPUB2 NCX fallback). XML is read with XMLDocument + local-name() XPaths,
//  which sidesteps namespace headaches without external dependencies.
//

import Foundation

// MARK: - Errors

enum EPUBDocumentError: LocalizedError {
    case missingContainer
    case missingPackage(String)
    case emptySpine
    case chapterIndexOutOfRange(Int)

    var errorDescription: String? {
        switch self {
        case .missingContainer:
            return "Not a valid EPUB: META-INF/container.xml is missing."
        case .missingPackage(let path):
            return "Not a valid EPUB: package document missing at \(path)."
        case .emptySpine:
            return "The EPUB has no readable chapters (empty spine)."
        case .chapterIndexOutOfRange(let index):
            return "Chapter index \(index) is out of range."
        }
    }
}

// MARK: - Model

struct EPUBManifestItem {
    let id: String
    /// Archive path, already resolved relative to the OPF location.
    let path: String
    let mediaType: String
    let properties: Set<String>
}

struct EPUBTOCEntry: Identifiable {
    let id = UUID()
    let title: String
    /// Resolved archive path of the target chapter (nil for unresolvable hrefs).
    let chapterPath: String?
    let fragment: String?
    /// Nesting depth for indented display (0 = top level).
    let depth: Int
}

// MARK: - Document

struct EPUBDocument {

    let title: String
    let author: String?
    let language: String?
    /// Reading-order archive paths (the spine).
    let spinePaths: [String]
    let tocEntries: [EPUBTOCEntry]
    let coverImagePath: String?

    private let archive: ZIPArchive
    private let manifestByPath: [String: EPUBManifestItem]

    var chapterCount: Int { spinePaths.count }

    // MARK: Init

    init(url: URL) throws {
        try self.init(archive: ZIPArchive(url: url))
    }

    init(archive: ZIPArchive) throws {
        self.archive = archive

        // 1. container.xml → package (OPF) path
        guard let containerData = try? archive.data(at: "META-INF/container.xml"),
              let containerXML = try? XMLDocument(data: containerData)
        else { throw EPUBDocumentError.missingContainer }

        guard let opfPath = (try? containerXML.nodes(
            forXPath: "//*[local-name()='rootfile']/@full-path"
        ))?.first?.stringValue, !opfPath.isEmpty
        else { throw EPUBDocumentError.missingContainer }

        // 2. OPF package document
        guard let opfData = try? archive.data(at: opfPath),
              let opf = try? XMLDocument(data: opfData)
        else { throw EPUBDocumentError.missingPackage(opfPath) }

        // Metadata (Dublin Core)
        func dcText(_ element: String) -> String? {
            (try? opf.nodes(forXPath: "//*[local-name()='metadata']/*[local-name()='\(element)']"))?
                .first?.stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        self.title = dcText("title") ?? "Untitled"
        self.author = dcText("creator")
        self.language = dcText("language")

        // Manifest
        var itemsByID: [String: EPUBManifestItem] = [:]
        for node in (try? opf.nodes(forXPath: "//*[local-name()='manifest']/*[local-name()='item']")) ?? [] {
            guard let element = node as? XMLElement,
                  let id = element.attribute(forName: "id")?.stringValue,
                  let href = element.attribute(forName: "href")?.stringValue
            else { continue }
            let item = EPUBManifestItem(
                id: id,
                path: Self.resolve(href: href, relativeTo: opfPath).path,
                mediaType: element.attribute(forName: "media-type")?.stringValue ?? "",
                properties: Set(
                    (element.attribute(forName: "properties")?.stringValue ?? "")
                        .split(separator: " ").map(String.init)
                )
            )
            itemsByID[id] = item
        }
        self.manifestByPath = Dictionary(
            itemsByID.values.map { ($0.path, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // Spine
        let spineIDs = ((try? opf.nodes(
            forXPath: "//*[local-name()='spine']/*[local-name()='itemref']/@idref"
        )) ?? []).compactMap(\.stringValue)
        let spine = spineIDs.compactMap { itemsByID[$0]?.path }
        guard !spine.isEmpty else { throw EPUBDocumentError.emptySpine }
        self.spinePaths = spine

        // Cover: EPUB3 `properties="cover-image"`, else EPUB2 <meta name="cover">
        if let coverItem = itemsByID.values.first(where: { $0.properties.contains("cover-image") }) {
            self.coverImagePath = coverItem.path
        } else if let coverID = (try? opf.nodes(
            forXPath: "//*[local-name()='metadata']/*[local-name()='meta'][@name='cover']/@content"
        ))?.first?.stringValue {
            self.coverImagePath = itemsByID[coverID]?.path
        } else {
            self.coverImagePath = nil
        }

        // TOC: EPUB3 nav document first, NCX fallback
        if let navItem = itemsByID.values.first(where: { $0.properties.contains("nav") }),
           let navData = try? archive.data(at: navItem.path),
           let entries = Self.parseNavTOC(navData, navPath: navItem.path),
           !entries.isEmpty {
            self.tocEntries = entries
        } else if let ncxID = (try? opf.nodes(forXPath: "//*[local-name()='spine']/@toc"))?.first?.stringValue,
                  let ncxItem = itemsByID[ncxID],
                  let ncxData = try? archive.data(at: ncxItem.path),
                  let entries = Self.parseNCXTOC(ncxData, ncxPath: ncxItem.path) {
            self.tocEntries = entries
        } else {
            self.tocEntries = []
        }
    }

    // MARK: Chapters & Resources

    func chapterPath(at index: Int) throws -> String {
        guard spinePaths.indices.contains(index) else {
            throw EPUBDocumentError.chapterIndexOutOfRange(index)
        }
        return spinePaths[index]
    }

    func chapterData(at index: Int) throws -> Data {
        try archive.data(at: chapterPath(at: index))
    }

    func chapterIndex(forPath path: String) -> Int? {
        spinePaths.firstIndex(of: path)
    }

    /// Raw resource bytes + MIME type (manifest first, extension fallback) —
    /// feeds the custom URL scheme handler in the reader view.
    func resource(at path: String) throws -> (data: Data, mimeType: String) {
        let data = try archive.data(at: path)
        if let declared = manifestByPath[path]?.mediaType, !declared.isEmpty {
            return (data, declared)
        }
        return (data, Self.mimeType(forExtension: (path as NSString).pathExtension))
    }

    func containsResource(at path: String) -> Bool {
        archive.contains(path)
    }

    /// Chapter text with markup stripped — powers in-book search.
    func plainText(at index: Int) -> String {
        guard let data = try? chapterData(at: index) else { return "" }
        if let xml = try? XMLDocument(data: data, options: [.documentTidyXML]),
           let text = xml.rootElement()?.stringValue {
            return text
        }
        // Malformed chapter: crude tag strip beats returning nothing.
        return String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
    }

    /// Best display title for a chapter: its TOC entry, else "Chapter N".
    func chapterTitle(at index: Int) -> String {
        guard spinePaths.indices.contains(index) else { return "" }
        let path = spinePaths[index]
        if let entry = tocEntries.first(where: { $0.chapterPath == path }) {
            return entry.title
        }
        return String(localized: "Chapter \(index + 1)")
    }

    // MARK: - TOC Parsers

    private static func parseNavTOC(_ data: Data, navPath: String) -> [EPUBTOCEntry]? {
        guard let xml = try? XMLDocument(data: data, options: [.documentTidyXML]) else { return nil }

        // The <nav epub:type="toc"> element; fall back to the first nav.
        let navNodes = (try? xml.nodes(
            forXPath: "//*[local-name()='nav'][@*[local-name()='type']='toc']"
        )) ?? []
        let tocNav = navNodes.first ?? (try? xml.nodes(forXPath: "//*[local-name()='nav']"))?.first
        guard let tocNav else { return nil }

        let anchors = (try? tocNav.nodes(forXPath: ".//*[local-name()='a']")) ?? []
        return anchors.compactMap { node in
            guard let element = node as? XMLElement,
                  let href = element.attribute(forName: "href")?.stringValue,
                  let text = element.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty
            else { return nil }
            let resolved = resolve(href: href, relativeTo: navPath)
            // Depth = enclosing <li> nesting relative to the nav root.
            var depth = 0
            var parent = element.parent as? XMLElement
            while let current = parent {
                if current.localName == "ol" || current.localName == "ul" { depth += 1 }
                parent = current.parent as? XMLElement
            }
            return EPUBTOCEntry(
                title: text,
                chapterPath: resolved.path.isEmpty ? nil : resolved.path,
                fragment: resolved.fragment,
                depth: max(0, depth - 1)
            )
        }
    }

    private static func parseNCXTOC(_ data: Data, ncxPath: String) -> [EPUBTOCEntry]? {
        guard let xml = try? XMLDocument(data: data) else { return nil }
        let navPoints = (try? xml.nodes(forXPath: "//*[local-name()='navPoint']")) ?? []

        return navPoints.compactMap { node in
            guard let element = node as? XMLElement,
                  let label = (try? element.nodes(
                    forXPath: ".//*[local-name()='navLabel']/*[local-name()='text']"
                  ))?.first?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !label.isEmpty,
                  let src = (try? element.nodes(
                    forXPath: ".//*[local-name()='content']/@src"
                  ))?.first?.stringValue
            else { return nil }
            let resolved = resolve(href: src, relativeTo: ncxPath)
            var depth = 0
            var parent = element.parent as? XMLElement
            while let current = parent {
                if current.localName == "navPoint" { depth += 1 }
                parent = current.parent as? XMLElement
            }
            return EPUBTOCEntry(
                title: label,
                chapterPath: resolved.path.isEmpty ? nil : resolved.path,
                fragment: resolved.fragment,
                depth: depth
            )
        }
    }

    // MARK: - Path Resolution

    /// Resolves a (possibly percent-encoded, possibly relative) href against
    /// the archive path of the document that references it.
    static func resolve(href: String, relativeTo basePath: String) -> (path: String, fragment: String?) {
        let decoded = href.removingPercentEncoding ?? href
        let hashSplit = decoded.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let rawPath = String(hashSplit[0])
        let fragment = hashSplit.count > 1 ? String(hashSplit[1]) : nil

        // Fragment-only href points into the same document.
        guard !rawPath.isEmpty else { return (basePath, fragment) }

        var components = basePath.split(separator: "/").dropLast().map(String.init)
        for part in rawPath.split(separator: "/") {
            switch part {
            case "..": if !components.isEmpty { components.removeLast() }
            case ".":  continue
            default:   components.append(String(part))
            }
        }
        return (components.joined(separator: "/"), fragment)
    }

    // MARK: - MIME

    private static func mimeType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "xhtml", "html", "htm": return "application/xhtml+xml"
        case "css":                  return "text/css"
        case "js":                   return "text/javascript"
        case "jpg", "jpeg":          return "image/jpeg"
        case "png":                  return "image/png"
        case "gif":                  return "image/gif"
        case "svg":                  return "image/svg+xml"
        case "webp":                 return "image/webp"
        case "ttf":                  return "font/ttf"
        case "otf":                  return "font/otf"
        case "woff":                 return "font/woff"
        case "woff2":                return "font/woff2"
        case "mp3":                  return "audio/mpeg"
        case "ncx":                  return "application/x-dtbncx+xml"
        default:                     return "application/octet-stream"
        }
    }
}
