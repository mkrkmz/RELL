//
//  ZenToolbar.swift
//  Reader for Language Learner
//
//  Zen mode's controls, in the window toolbar (v14 S1). Zen is full screen,
//  and in full screen macOS slides the title bar down over the top of the
//  window whenever the pointer reaches the menu bar. A custom bar revealed
//  there (v1.30–v14 S1) sat under that title bar and its buttons stopped
//  taking clicks once the page reached the top of the screen. So Zen uses
//  the toolbar itself: hidden until the pointer goes up, then shown with the
//  menu bar — the system's own full-screen behaviour.
//

import SwiftUI

/// The View-menu commands useful without leaving Zen.
struct ZenControls {
    /// Nil where meanings can't show (PDF).
    var glossesOn: Bool?
    var toggleGlosses: () -> Void
    var readAloud: () -> Void
    var exit: () -> Void
}

extension ContentView {
    /// The toolbar for the window: the reader's own, or Zen's.
    @ToolbarContentBuilder
    var windowToolbarContent: some ToolbarContent {
        if zenMode {
            zenToolbarContent
        } else {
            toolbarContent
        }
    }

    @ToolbarContentBuilder
    private var zenToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            if isEPUBDocument {
                // v18 S4: where you are, as in the PDF's scrubber.
                Text(pageStatusText)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
            } else if pdfViewManager.pageCount > 1 {
                HStack(spacing: DS.Spacing.sm) {
                    PageScrubberView(
                        currentPageIndex: pdfViewManager.currentPageIndex,
                        pageCount: pdfViewManager.pageCount
                    ) { pdfViewManager.goToPage(index: $0) }
                    .frame(width: 220)
                    Text("\((pdfViewManager.currentPageIndex ?? 0) + 1) / \(pdfViewManager.pageCount)")
                        .font(DS.Typography.mono)
                        .foregroundStyle(DS.Color.textSecondary)
                        .monospacedDigit()
                }
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            let controls = zenControls
            if let glossesOn = controls.glossesOn {
                Toggle(isOn: Binding(get: { glossesOn }, set: { _ in controls.toggleGlosses() })) {
                    Label("Show Meanings Above Words", systemImage: "character.textbox")
                }
                .help("Show Meanings Above Words")
            }

            // v18 S4: the reader's own "Aa" panel — theme and type
            // without leaving Zen.
            Button { showReadingAppearance.toggle() } label: {
                Label("Reading Appearance", systemImage: "textformat.size")
            }
            .help("Reading Appearance")
            .popover(isPresented: Bindable(model).showReadingAppearance, arrowEdge: .bottom) {
                ReadingAppearanceView(isEPUB: isEPUBDocument)
            }

            Button(action: controls.readAloud) {
                Label("Read Page Aloud", systemImage: "speaker.wave.2")
            }
            .help("Read Page Aloud")

            Button(action: controls.exit) {
                Label("Exit Zen Mode", systemImage: "arrow.down.right.and.arrow.up.left")
            }
            .help("Exit Zen Mode")
        }
    }
}
