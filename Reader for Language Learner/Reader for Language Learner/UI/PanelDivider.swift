//
//  PanelDivider.swift
//  Reader for Language Learner
//
//  Extracted from ContentView.swift
//

import AppKit
import SwiftUI

struct PanelDivider: View {
    @Binding var panelWidth: Double
    let minWidth: Double
    let maxWidth: Double
    let panelOnLeadingSide: Bool
    let defaultWidth: Double

    @State private var dragStartWidth: Double = 0
    @State private var isDragging = false
    @State private var isHovering = false

    var body: some View {
        Rectangle()
            .fill(isHovering ? DS.Color.accentMuted : DS.Color.separator)
            .frame(width: 1)
            .padding(.horizontal, 3)
            .frame(width: 7)
            .contentShape(Rectangle())
            .animation(DS.Animation.fast, value: isHovering)
            .onHover { hovering in
                isHovering = hovering
                hovering ? NSCursor.resizeLeftRight.push() : NSCursor.pop()
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if !isDragging { isDragging = true; dragStartWidth = panelWidth }
                        let delta = panelOnLeadingSide
                            ? value.translation.width
                            : -value.translation.width
                        panelWidth = max(minWidth, min(maxWidth, dragStartWidth + delta))
                    }
                    .onEnded { _ in isDragging = false }
            )
            .onTapGesture(count: 2) {
                withAnimation(DS.Animation.spring) { panelWidth = defaultWidth }
            }
    }
}
