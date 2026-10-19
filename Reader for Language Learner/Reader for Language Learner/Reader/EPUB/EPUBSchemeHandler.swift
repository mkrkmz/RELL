//
//  EPUBSchemeHandler.swift
//  Reader for Language Learner
//
//  The reader's custom URL scheme and the selection anchor. Split out of
//  EPUBViewManager.swift (v19 S0), unchanged.
//

import Foundation
import os
import SwiftUI
import WebKit

// MARK: - URL Scheme

enum EPUBScheme {
    static let scheme = "rell-epub"

    static func url(forArchivePath path: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "book"
        components.path = "/" + path
        return components.url
    }

    static func archivePath(from url: URL) -> String {
        String(url.path.dropFirst())   // strip leading "/" — already percent-decoded
    }
}

// MARK: - Scheme Handler

/// Serves chapter XHTML and its resources (images, CSS, fonts) straight from
/// the ZIP archive. WebKit's protocol is main-actor isolated, so these run
/// on the main actor like the rest of the reader.
final class EPUBSchemeHandler: NSObject, WKURLSchemeHandler {
    /// Off the main actor: on macOS 15 a main-actor deinit run outside a
    /// task crashes when it releases another one (v16 S0, CI crash reports).
    nonisolated deinit {}


    var document: EPUBDocument?

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let document
        else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        let path = EPUBScheme.archivePath(from: url)
        do {
            let resource = try document.resource(at: path)
            let response = URLResponse(
                url: url,
                mimeType: resource.mimeType,
                expectedContentLength: resource.data.count,
                textEncodingName: resource.mimeType.contains("xml") || resource.mimeType.hasPrefix("text")
                    ? "utf-8" : nil
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(resource.data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Loads are synchronous slices from memory — nothing to cancel.
    }
}

// MARK: - Selection Anchor

/// Text-quote selector for a live selection — mirrors the W3C Web
/// Annotation model closely enough for our purposes: enough context to
/// re-find the same text after a chapter reload, independent of any fixed
/// geometry (EPUB has none).
struct EPUBSelectionAnchor: Equatable {
    let quote: String
    let prefix: String
    let suffix: String
    let startOffset: Int
}
