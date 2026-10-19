//
//  EPUBViewManager+WebKit.swift
//  Reader for Language Learner
//
//  The link policy and the web view's navigation and message delegates.
//  Split out of EPUBViewManager.swift (v19 S0), unchanged.
//

import Foundation
import os
import SwiftUI
import WebKit

// MARK: - Link policy

/// Where a navigation inside the reader may go. Book-internal pages load in
/// place. Anything else leaves the app only when the reader clicked it and it
/// is a web or mail link — never a `file://` URL or another app's scheme,
/// and never on the page's own initiative (a redirect, a meta refresh).
enum EPUBLinkPolicy: Equatable {
    case allow
    case openExternally(URL)
    case block

    static let externalSchemes: Set<String> = ["http", "https", "mailto"]

    static func decision(for url: URL?, userClicked: Bool) -> EPUBLinkPolicy {
        guard let url, let scheme = url.scheme?.lowercased() else { return .block }
        if scheme == EPUBScheme.scheme || scheme == "about" { return .allow }
        guard userClicked, externalSchemes.contains(scheme) else { return .block }
        return .openExternally(url)
    }
}

// MARK: - WKNavigationDelegate

extension EPUBViewManager: WKNavigationDelegate {

    nonisolated func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        MainActor.assumeIsolated {
            switch EPUBLinkPolicy.decision(
                for: navigationAction.request.url,
                userClicked: navigationAction.navigationType == .linkActivated
            ) {
            case .allow:
                decisionHandler(.allow)
            case .openExternally(let url):
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            case .block:
                decisionHandler(.cancel)
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated {
            chapterDidFinishLoading(url: webView.url)
        }
    }
}

// MARK: - WKScriptMessageHandler

extension EPUBViewManager: WKScriptMessageHandler {

    static let scrollMessageName = "rellScroll"
    static let selectionMessageName = "rellSelection"
    static let hoverMessageName = "rellHover"

    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        MainActor.assumeIsolated {
            switch message.name {
            case Self.scrollMessageName:
                if let fraction = message.body as? Double {
                    handleScrollMessage(fraction: fraction)
                }
            case Self.selectionMessageName:
                if let body = message.body as? [String: Any] {
                    let rect = CGRect(
                        x: (body["rectX"] as? Double) ?? -1,
                        y: (body["rectY"] as? Double) ?? -1,
                        width: (body["rectW"] as? Double) ?? 0,
                        height: (body["rectH"] as? Double) ?? 0
                    )
                    // Scroll-driven reposition carries only a fresh rect.
                    if (body["reposition"] as? Bool) == true {
                        repositionSelectionBar(rect: rect)
                        break
                    }
                    let text = (body["text"] as? String) ?? ""
                    var anchor: EPUBSelectionAnchor?
                    if !text.isEmpty,
                       let quote = body["quote"] as? String, !quote.isEmpty,
                       let startOffset = body["startOffset"] as? Int {
                        anchor = EPUBSelectionAnchor(
                            quote: quote,
                            prefix: (body["prefix"] as? String) ?? "",
                            suffix: (body["suffix"] as? String) ?? "",
                            startOffset: startOffset
                        )
                    }
                    handleSelectionMessage(
                        text: text,
                        sentence: body["sentence"] as? String,
                        anchor: anchor,
                        rect: rect
                    )
                }
            case Self.hoverMessageName:
                if let body = message.body as? [String: Any] {
                    handleHoverMessage(
                        word: (body["word"] as? String) ?? "",
                        rect: CGRect(
                            x: (body["x"] as? Double) ?? 0,
                            y: (body["y"] as? Double) ?? 0,
                            width: (body["w"] as? Double) ?? 0,
                            height: (body["h"] as? Double) ?? 0
                        )
                    )
                }
            default:
                break
            }
        }
    }
}
