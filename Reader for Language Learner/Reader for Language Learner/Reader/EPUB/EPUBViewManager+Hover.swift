//
//  EPUBViewManager+Hover.swift
//  Reader for Language Learner
//
//  The hover dictionary. Split out of EPUBViewManager.swift (v19 S0),
//  unchanged.
//

import Foundation
import os
import SwiftUI
import WebKit

extension EPUBViewManager {

    // MARK: Hover dictionary

    func handleHoverMessage(word: String, rect: CGRect) {
        guard hoverEnabled, let webView, document != nil else { return }
        let term = word.trimmingCharacters(in: .whitespacesAndNewlines)

        guard (1...40).contains(term.count),
              term.contains(where: \.isLetter),
              !term.contains(where: \.isWhitespace)
        else {
            closeHoverPopover()
            return
        }
        if term.lowercased() == currentHoverTerm.lowercased(), hoverBalloon.isShown {
            return
        }
        currentHoverTerm = term

        if !hoverModel.begin(term: term, isSaved: hoverIsSaved?(term) ?? false, cached: hoverCachedLookup?(term)) {
            startHoverLookup(term: term)
        }

        // WKWebView is flipped, so JS viewport coordinates map straight
        // onto the view's coordinate space.
        let positioning = rect.width > 0 ? rect : CGRect(x: rect.minX, y: rect.minY, width: 1, height: 1)
        hoverBalloon.show(at: positioning, in: webView)
    }

    private func startHoverLookup(term: String) {
        hoverTask?.cancel()
        hoverTask = Task { @MainActor [weak self] in
            guard let self, let lookup = self.hoverLookup else { return }
            do {
                let answer = try await lookup(term)
                guard !Task.isCancelled,
                      self.currentHoverTerm.lowercased() == term.lowercased() else { return }
                self.hoverModel.show(answer)
            } catch {
                guard !Task.isCancelled,
                      self.currentHoverTerm.lowercased() == term.lowercased() else { return }
                self.hoverModel.fail()
            }
        }
    }

    func closeHoverPopover() {
        hoverTask?.cancel()
        currentHoverTerm = ""
        hoverBalloon.close()
    }
}
