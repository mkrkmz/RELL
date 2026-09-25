//
//  ContentView+Toolbar.swift
//  Reader for Language Learner
//
//  Window toolbar and zoom controls.
//

import AppKit
import CoreSpotlight
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

extension ContentView {
    // MARK: - Toolbar

    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            if selectionState.documentURL != nil {
                Button(action: closeDocument) {
                    Label("Home", systemImage: "house")
                }
                .help("Close document and return to Home (⇧⌘W)")
                .accessibilityLabel("Return to Home")
            }
        }

        // NavigationSplitView supplies the system sidebar toggle.

        ToolbarItem(placement: .navigation) {
            if selectionState.documentURL != nil, !isEPUBDocument {
                HStack(spacing: DS.Spacing.sm) {
                    PageIndicatorView(
                        currentPageIndex: pdfViewManager.currentPageIndex,
                        pageCount: pdfViewManager.pageCount
                    ) { index in
                        pdfViewManager.goToPage(index: index)
                    }

                    if pdfViewManager.pageCount > 1 {
                        PageScrubberView(
                            currentPageIndex: pdfViewManager.currentPageIndex,
                            pageCount: pdfViewManager.pageCount
                        ) { index in
                            pdfViewManager.goToPage(index: index)
                        }
                        .frame(width: 130)
                    }
                }
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: openPDF) {
                Label("Open", systemImage: "folder.badge.plus")
            }
            .help("Open a PDF or EPUB (⌘O)")

            Button(action: openFindBar) {
                Label("Find", systemImage: "magnifyingglass")
            }
            .keyboardShortcut("f", modifiers: [.command])
            .help("Find (⌘F)")
            .disabled(selectionState.documentURL == nil)

            Button(action: toggleCurrentPageBookmark) {
                Label(
                    "Bookmark",
                    systemImage: isCurrentPageBookmarked ? "bookmark.fill" : "bookmark"
                )
            }
            .keyboardShortcut("b", modifiers: [.command])
            .help(isCurrentPageBookmarked ? "Remove Bookmark (⌘B)" : "Bookmark Page (⌘B)")
            .disabled(selectionState.documentURL == nil)
        }

        ToolbarItemGroup(placement: .automatic) {
            if selectionState.documentURL != nil {
                if !isEPUBDocument {
                    zoomControls
                    Button { pdfViewManager.fitToWidth() } label: {
                        Label("Fit Width", systemImage: "arrow.left.and.right.text.vertical")
                    }
                    .help("Fit to Width (⌘0)")
                    .keyboardShortcut("0", modifiers: [.command])
                }

                // "Aa" — page theme for both formats, typography for EPUB.
                // EPUB text-size stepping keeps its ⌘+/⌘− shortcuts through
                // the View menu (ReaderCommands zoomIn/zoomOut), which was
                // already the canonical path.
                Button { showReadingAppearance.toggle() } label: {
                    Label("Reading Appearance", systemImage: "textformat.size")
                }
                .help("Reading Appearance")
                .popover(isPresented: Bindable(model).showReadingAppearance, arrowEdge: .bottom) {
                    ReadingAppearanceView(isEPUB: isEPUBDocument)
                }
            }
        }

        ToolbarItem(placement: .automatic) {
            Menu {
                Section("App Theme") {
                    ForEach(AppTheme.allCases) { theme in
                        Button { appThemeRaw = theme.rawValue } label: {
                            HStack {
                                Label(theme.localizedTitle, systemImage: theme.iconName)
                                if appTheme == theme { Spacer(); Image(systemName: "checkmark") }
                            }
                        }
                    }
                }
                Section("Page Theme") {
                    ForEach(PageTheme.allCases) { theme in
                        Button { pageThemeRaw = theme.rawValue } label: {
                            HStack {
                                Label(theme.localizedTitle, systemImage: theme.iconName)
                                if pageTheme == theme { Spacer(); Image(systemName: "checkmark") }
                            }
                        }
                    }
                }
            } label: {
                Label("Theme", systemImage: "paintbrush")
            }
            .help("App & Page Themes")
        }

        ToolbarItem(placement: .automatic) {
            Button { toggleFocusMode() } label: {
                Label(
                    "Focus Mode",
                    systemImage: focusMode
                        ? "arrow.down.right.and.arrow.up.left"
                        : "arrow.up.left.and.arrow.down.right"
                )
            }
            .help(focusMode ? "Exit Focus Mode (⇧⌘D)" : "Focus Mode — hide panels (⇧⌘D)")
            .disabled(selectionState.documentURL == nil)
        }

        ToolbarItem(placement: .automatic) {
            Button { showStats = true } label: {
                Label("Stats", systemImage: "chart.bar")
            }
            .help("Reading & vocabulary stats")
        }

        ToolbarItem(placement: .status) {
            LLMStatusItem(health: llmHealth, circuitBreaker: circuitBreaker)
        }

        ToolbarItem(placement: .automatic) {
            Button { toggleInspector() } label: {
                Label("Toggle Inspector", systemImage: "sidebar.right")
            }
            .help("Toggle Inspector (⌘⌥I)")
        }
    }

    var zoomControls: some View {
        HStack(spacing: 0) {
            Button { pdfViewManager.zoomOut() } label: {
                Image(systemName: "minus")
                    .frame(width: 26, height: 22)
                    .contentShape(Rectangle())
            }
            .help("Zoom Out (⌘-)")
            .accessibilityLabel(Text("Zoom Out"))
            .keyboardShortcut("-", modifiers: [.command])

            Divider().frame(height: 16)

            Text(pdfViewManager.zoomLabel)
                .font(DS.Typography.mono)
                .foregroundStyle(DS.Color.textSecondary)
                .frame(width: 46)
                .onTapGesture { pdfViewManager.fitToWidth() }

            Divider().frame(height: 16)

            Button { pdfViewManager.zoomIn() } label: {
                Image(systemName: "plus")
                    .frame(width: 26, height: 22)
                    .contentShape(Rectangle())
            }
            .help("Zoom In (⌘+)")
            .accessibilityLabel(Text("Zoom In"))
            .keyboardShortcut("+", modifiers: [.command])
        }
        .buttonStyle(.borderless)
        .background(DS.Color.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.sm)
                .strokeBorder(DS.Color.separator, lineWidth: 0.5)
        )
    }
}
