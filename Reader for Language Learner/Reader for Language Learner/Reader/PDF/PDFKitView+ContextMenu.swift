//
//  PDFKitView+ContextMenu.swift
//  Reader for Language Learner
//
//  The PDF reader's context-menu actions. Split out of
//  PDFKitView+Coordinator.swift (v19 S0), unchanged.
//

import NaturalLanguage
import os
import PDFKit
import QuartzCore
import SwiftUI

extension PDFKitView.Coordinator {

        // MARK: - Context Menu Actions

        func contextSaveWord() {
            guard let pdfView = pdfView,
                  let raw = pdfView.currentSelection?.string else { return }
            let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { return }

            let sentence = extractContext() ?? ""
            let filename = loadedDocumentURL?.deletingPathExtension().lastPathComponent
            let documentPath = loadedDocumentURL?.path
            let pageNum: Int?
            if let page = pdfView.currentPage {
                pageNum = (pdfView.document?.index(for: page)).map { $0 + 1 }
            } else {
                pageNum = nil
            }
            Task { @MainActor in
                self.savedWordsStore.add(SavedWord(
                    term: term,
                    sentence: sentence,
                    pdfFilename: filename,
                    pageNumber: pageNum,
                    mode: ExplainMode.word.rawValue,
                    domain: "general",
                    llmOutputs: [:],
                    language: Language.storedTarget.rawValue,
                    documentPath: documentPath
                ))
                self.toastCenter.show(String(localized: "Word saved!"))
            }
        }

        func contextAddNote() {
            guard let pdfView = pdfView,
                  let selection = pdfView.currentSelection,
                  let raw = selection.string
            else { return }
            let selectedText = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !selectedText.isEmpty else { return }

            guard let page = selection.pages.first ?? pdfView.currentPage,
                  let document = pdfView.document
            else { return }

            let pageIndex = document.index(for: page)
            let rects = selection.selectionsByLine().map { lineSelection in
                let rect = lineSelection.bounds(for: page)
                return PDFHighlightRect(
                    x: rect.origin.x,
                    y: rect.origin.y,
                    width: rect.size.width,
                    height: rect.size.height
                )
            }

            let draft = PDFNote(
                pdfFilename: loadedDocumentURL?.deletingPathExtension().lastPathComponent ?? "Unknown PDF",
                pageIndex: pageIndex,
                pageLabel: page.label ?? "Page \(pageIndex + 1)",
                selectedText: selectedText,
                contextSentence: extractContext() ?? "",
                note: "",
                category: .vocabulary,
                highlightRects: rects
            )

            Task { @MainActor in
                self.noteStore.startDraft(draft)
            }
        }

        func contextHighlight(_ color: HighlightColor) {
            guard let pdfView = pdfView,
                  let selection = pdfView.currentSelection,
                  let raw = selection.string
            else { return }
            let selectedText = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !selectedText.isEmpty else { return }

            guard let page = selection.pages.first ?? pdfView.currentPage,
                  let document = pdfView.document
            else { return }

            let pageIndex = document.index(for: page)
            let rects = selection.selectionsByLine().map { lineSelection -> PDFHighlightRect in
                let rect = lineSelection.bounds(for: page)
                return PDFHighlightRect(
                    x: rect.origin.x,
                    y: rect.origin.y,
                    width: rect.size.width,
                    height: rect.size.height
                )
            }
            guard !rects.isEmpty else { return }

            let highlight = PDFHighlight(
                pdfFilename: loadedDocumentURL?.deletingPathExtension().lastPathComponent ?? "Unknown PDF",
                pageIndex: pageIndex,
                pageLabel: page.label ?? "Page \(pageIndex + 1)",
                selectedText: selectedText,
                colorRaw: color.rawValue,
                highlightRects: rects
            )

            Task { @MainActor in
                self.highlightStore.add(highlight)
            }
        }

        func contextCopy() {
            guard let text = pdfView?.currentSelection?.string, !text.isEmpty else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }

        func contextSpeak() {
            guard let raw = pdfView?.currentSelection?.string else { return }
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            Task { @MainActor in
                SpeechManager.shared.speakResolved(text)
            }
        }
}
