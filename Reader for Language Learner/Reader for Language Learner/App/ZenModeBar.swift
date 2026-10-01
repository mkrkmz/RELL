//
//  ZenModeBar.swift
//  Reader for Language Learner
//
//  The only chrome shown in zen mode: a slim strip at the top of the reader
//  that stays out of the way until the pointer approaches, then reveals a
//  minimal glass bar with the document title, reading position, and an exit
//  control. Keeps immersive reading immersive while leaving a way back.
//

import SwiftUI

struct ZenModeBar: View {
    let title: String
    let subtitle: String
    let onExit: () -> Void
    /// Page navigation for the zen bar (U-X2). The toolbar is hidden in zen
    /// mode, so without this the only way through a document is scrolling.
    /// Paginated documents only — nil leaves the slot empty.
    var currentPageIndex: Int? = nil
    var pageCount: Int = 0
    var onNavigate: ((Int) -> Void)? = nil
    /// Reading controls that are useful without leaving zen mode (v14 S1):
    /// the same commands as the View menu and ⌘K.
    var controls: Controls? = nil

    struct Controls {
        /// Nil where meanings can't show (PDF).
        var glossesOn: Bool?
        var toggleGlosses: () -> Void
        var pageTheme: PageTheme
        var setPageTheme: (PageTheme) -> Void
        var readAloud: () -> Void
    }

    @State private var revealed = false
    @State private var monitor: Any?
    /// True while the pointer is on the bar itself — the bar is a real view
    /// once it's up, so its own hover is what decides when it goes away.
    @State private var barHovered = false

    var body: some View {
        Group {
            if revealed {
                bar
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else {
                // Nothing to show, and nothing to hit-test: the pointer is
                // tracked by the window, not by a view (see `startWatching`).
                SwiftUI.Color.clear.frame(height: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .onAppear { startWatching() }
        .onDisappear { stopWatching() }
    }

    // MARK: - Pointer watch

    /// Reveal on the pointer approaching the top of the window, watched
    /// through an event monitor rather than a hover region.
    ///
    /// A hover region is a poor fit here. It has to be hit-testable to
    /// receive hover, so an invisible band over the page swallows clicks —
    /// which caps its useful height, and the 6pt band this replaces (v1.30)
    /// sat exactly where full screen summons the menu bar, which then owns
    /// those pixels. Watching the pointer instead costs nothing at rest,
    /// takes no clicks, and can use a band deep enough to aim at.
    private static let revealDistance: CGFloat = 52

    /// Escape hatch for a pointer that leaves without ever crossing the bar
    /// (sideways, or in one jump). Generous, because closing is the bar's own
    /// job — see `barHovered`.
    private static let abandonDistance: CGFloat = 320

    private func startWatching() {
        NSApp.keyWindow?.acceptsMouseMovedEvents = true
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { event in
            // Deliberately not filtered to this bar's own window: in full
            // screen the event's window isn't reliably the key window, and
            // gating on that stopped the reveal entirely. A second zen window
            // can hold a stale reveal until the pointer returns to it, which
            // is invisible — zen mode is full screen, one window at a time.
            guard let window = event.window, let contentView = window.contentView
            else { return event }
            window.acceptsMouseMovedEvents = true
            let point = contentView.convert(event.locationInWindow, from: nil)
            // SwiftUI's hosting view is flipped, so its y already counts down
            // from the top; an AppKit content view counts up from the bottom.
            let fromTop = contentView.isFlipped ? point.y : contentView.bounds.height - point.y

            // The monitor only opens the bar. It measures from the top of
            // the content view, while the bar draws below the window's title
            // inset — so a "still near the top?" test in this space closes it
            // exactly as the pointer arrives on it, which is what made the
            // bar dodge the pointer and swallow its own clicks.
            if fromTop <= Self.revealDistance {
                if !revealed { withAnimation(DS.Animation.standard) { revealed = true } }
            } else if revealed, !barHovered, fromTop > Self.abandonDistance {
                withAnimation(DS.Animation.standard) { revealed = false }
            }
            return event
        }
    }

    private func stopWatching() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        revealed = false
    }

    private var bar: some View {
        HStack(spacing: DS.Spacing.md) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(DS.Typography.headline)
                    .lineLimit(1)
                    .foregroundStyle(DS.Color.textPrimary)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: DS.Spacing.md)

            if let onNavigate, pageCount > 1 {
                PageScrubberView(
                    currentPageIndex: currentPageIndex,
                    pageCount: pageCount,
                    onNavigate: onNavigate
                )
                .frame(width: 220)

                Text("\((currentPageIndex ?? 0) + 1) / \(pageCount)")
                    .font(DS.Typography.mono)
                    .foregroundStyle(DS.Color.textSecondary)
                    .monospacedDigit()
            }

            if let controls {
                readingControls(controls)
                Divider().frame(height: 18)
            }

            Button(action: onExit) {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(DS.Typography.icon(15, weight: .medium))
                    .foregroundStyle(DS.Color.textPrimary)
                    .padding(DS.Spacing.xs)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Exit Zen Mode")
            .accessibilityLabel("Exit Zen Mode")
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
        .frame(maxWidth: .infinity)
        .dsGlassCard(radius: 0, fallback: AnyShapeStyle(.regularMaterial), fallbackShadow: DS.Shadow.float)
        .onHover { hovering in
            if hovering {
                barHovered = true
            } else if barHovered {
                // Only a pointer that actually reached the bar can dismiss it
                // by leaving. A stray `false` while it animates in must not
                // close what just opened.
                barHovered = false
                withAnimation(DS.Animation.standard) { revealed = false }
            }
        }
    }

    private func readingControls(_ controls: Controls) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            if let glossesOn = controls.glossesOn {
                Button(action: controls.toggleGlosses) {
                    controlIcon("character.textbox", active: glossesOn)
                }
                .buttonStyle(.plain)
                .help("Show Meanings Above Words")
                .accessibilityLabel("Show Meanings Above Words")
                .accessibilityValue(glossesOn ? Text("On") : Text("Off"))
            }

            Menu {
                ForEach(PageTheme.allCases) { theme in
                    Button {
                        controls.setPageTheme(theme)
                    } label: {
                        if controls.pageTheme == theme {
                            Label(theme.localizedTitle, systemImage: "checkmark")
                        } else {
                            Text(theme.localizedTitle)
                        }
                    }
                }
            } label: {
                controlIcon("circle.lefthalf.filled", active: false)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Page Theme")
            .accessibilityLabel("Page Theme")

            Button(action: controls.readAloud) {
                controlIcon("speaker.wave.2", active: false)
            }
            .buttonStyle(.plain)
            .help("Read Page Aloud")
            .accessibilityLabel("Read Page Aloud")
        }
    }

    private func controlIcon(_ name: String, active: Bool) -> some View {
        Image(systemName: name)
            .font(DS.Typography.icon(14, weight: .medium))
            .foregroundStyle(active ? DS.Color.accent : DS.Color.textPrimary)
            .frame(width: 26, height: 24)
            .contentShape(Rectangle())
    }
}
