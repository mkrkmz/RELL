//
//  HoverDefinitionPopover.swift
//  Reader for Language Learner
//
//  The hover dictionary balloon (HoverBalloon) and its content. Driven by HoverLookupModel,
//  which the PDF coordinator updates as a definition resolves.
//

import AppKit
import SwiftUI

/// The hover balloon at a word, in both readers (1.48 live pass).
///
/// It used to be an `NSPopover`. Measured in the PDF reader, the popover
/// opened up to ~240 pt above or below the word it was given — the word's
/// rectangle was right, the popover didn't keep to it — so it often sat far
/// from the word. The selection bar, a subview placed with frames from the
/// same rectangles, always landed right; the balloon now works the same way:
/// a view inside the page, below the word (above when there's no room),
/// letting the pointer through so hovering and selecting go on underneath.
@MainActor
final class HoverBalloon {
    /// How long the pointer rests on a word before the balloon opens, in
    /// both readers. 0.8 s since 1.48 (0.5 s before): passing over the text
    /// on the way somewhere no longer opens one.
    nonisolated static let delay: TimeInterval = 0.8

    private let model: HoverLookupModel
    private var host: HoverBalloonHostingView?
    /// The word's rectangle in the host view, and that view.
    private var anchor: (rect: CGRect, view: NSView)?

    init(model: HoverLookupModel) {
        self.model = model
    }

    var isShown: Bool { host?.superview != nil }

    /// Shows the balloon at `rect`, a rectangle in `view`'s coordinates.
    func show(at rect: CGRect, in view: NSView) {
        anchor = (rect, view)
        let host = self.host ?? HoverBalloonHostingView(rootView: HoverBalloonView(model: model))
        host.translatesAutoresizingMaskIntoConstraints = true
        if host.superview !== view {
            host.removeFromSuperview()
            view.addSubview(host)
        }
        self.host = host
        layout()
        track()
    }

    func close() {
        host?.removeFromSuperview()
        anchor = nil
    }

    /// Re-placed whenever the answer changes its size (loading → loaded).
    private func track() {
        withObservationTracking {
            _ = model.phase
            _ = model.source
            _ = model.term
            _ = model.isSaved
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isShown else { return }
                self.layout()
                self.track()
            }
        }
    }

    private func layout() {
        guard let host, let (rect, view) = anchor else { return }
        let size = host.fittingSize
        let visible = view.visibleRect
        let origin: CGPoint
        if view.isFlipped {
            origin = CGPoint(
                x: HoverBalloonPlacement.originX(wordMidX: rect.midX, width: size.width,
                                                 visibleLeft: visible.minX, visibleRight: visible.maxX),
                y: HoverBalloonPlacement.originY(wordTop: rect.minY, wordBottom: rect.maxY, height: size.height,
                                                 visibleTop: visible.minY, visibleBottom: visible.maxY))
        } else {
            // Not flipped (PDFView): the rule runs on mirrored y.
            let top = HoverBalloonPlacement.originY(wordTop: -rect.maxY, wordBottom: -rect.minY, height: size.height,
                                                    visibleTop: -visible.maxY, visibleBottom: -visible.minY)
            origin = CGPoint(
                x: HoverBalloonPlacement.originX(wordMidX: rect.midX, width: size.width,
                                                 visibleLeft: visible.minX, visibleRight: visible.maxX),
                y: -top - size.height)
        }
        host.frame = CGRect(origin: origin, size: size)
    }
}

/// Where the balloon goes: below the word, above it when there's no room
/// below, never on the word while either side has room. Top-left space.
nonisolated enum HoverBalloonPlacement {
    static let gap: CGFloat = 4
    static let margin: CGFloat = 4

    static func originY(wordTop: CGFloat, wordBottom: CGFloat, height: CGFloat,
                        visibleTop: CGFloat, visibleBottom: CGFloat) -> CGFloat {
        let below = wordBottom + gap
        if below + height <= visibleBottom - margin { return below }
        let above = wordTop - gap - height
        if above >= visibleTop + margin { return above }
        return max(visibleTop + margin, visibleBottom - margin - height)
    }

    static func originX(wordMidX: CGFloat, width: CGFloat, visibleLeft: CGFloat, visibleRight: CGFloat) -> CGFloat {
        let centred = wordMidX - width / 2
        return min(max(centred, visibleLeft + margin), max(visibleLeft + margin, visibleRight - width - margin))
    }
}

/// The balloon's hosting view; the pointer goes through it. Not generic:
/// CI's Swift 6.3 optimizer crashed on the deinit of a generic
/// `NSHostingView` subclass in Release builds (1.48.1 release run).
final class HoverBalloonHostingView: NSHostingView<HoverBalloonView> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The balloon on the page's own surface, with room for its shadow.
struct HoverBalloonView: View {
    let model: HoverLookupModel

    var body: some View {
        HoverDefinitionPopover(model: model)
            .padding(DS.Spacing.sm)
    }
}

@MainActor
@Observable
final class HoverLookupModel {
    /// Off the main actor: on macOS 15 a main-actor deinit run outside a
    /// task crashes when it releases another one (v16 S0, CI crash reports).
    nonisolated deinit {}

    enum Phase: Equatable {
        case loading
        case loaded(String)
        case failed
    }

    var term: String = ""
    var phase: Phase = .loading
    /// Where the answer came from (v18 S4), shown under it.
    var source: HoverSource?
    /// The word is in your notebook (in any form of it).
    var isSaved = false

    /// A new word: its saved state, and the cached answer if there is one.
    /// False when it still has to be looked up.
    func begin(term: String, isSaved: Bool, cached: HoverAnswer?) -> Bool {
        self.term = term
        self.isSaved = isSaved
        if let cached {
            show(cached)
            return true
        }
        phase = .loading
        source = nil
        return false
    }

    func show(_ answer: HoverAnswer) {
        // v19 S0: from the dictionary, the short meaning, as on the card.
        phase = .loaded(answer.shortMeaning(for: term))
        source = answer.source
    }

    func fail() {
        phase = .failed
        source = nil
    }
}

/// The hover balloon (v18 S4, approved mockup): the word, a short answer of
/// at most four lines, and where it came from — on the page's own surface.
struct HoverDefinitionPopover: View {
    let model: HoverLookupModel

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.xs) {
                Text(model.term)
                    .font(DS.Typography.headline)
                    .foregroundStyle(DS.Color.textPrimary)
                    .lineLimit(1)
                if model.isSaved {
                    Text("saved")
                        .font(DS.Typography.caption2.weight(.semibold))
                        .foregroundStyle(DS.Color.success)
                        .padding(.horizontal, DS.Spacing.xs)
                        .background(DS.Color.success.opacity(0.14), in: Capsule())
                }
            }

            content

            if let source = model.source {
                Text(source.label)
                    .font(DS.Typography.caption2)
                    .foregroundStyle(DS.Color.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(DS.Spacing.md)
        .frame(width: 264, alignment: .leading)
        // Shown over the text: opaque and page-themed, not glass (v14 S1).
        .dsReadingOverlay(RoundedRectangle(cornerRadius: DS.Radius.md))
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            HStack(spacing: DS.Spacing.sm) {
                ProgressView().controlSize(.small)
                Text("Looking up…")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Color.textTertiary)
            }
        case .loaded(let definition):
            Text(definition)
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Color.textSecondary)
                .lineSpacing(3)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        case .failed:
            Text("No definition found. Select the word to ask in the Inspector.")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
