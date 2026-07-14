//
//  SpeechPlaybackBar.swift
//  Reader for Language Learner
//
//  Floating playback control shown while SpeechManager is speaking or
//  paused — play/pause, stop, progress, and a quick rate picker. Hosted by
//  ContentView's withSpeechPlayback(_:) stage, visible for both the
//  selection-based Speak button and "Read Page Aloud".
//

import SwiftUI

struct SpeechPlaybackBar: View {
    var manager: SpeechManager

    @AppStorage("speechRate") private var speechRate: Double = 0.5

    private static let ratePresets: [Double] = [0.4, 0.5, 0.6]

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            Button {
                manager.state == .paused ? manager.resume() : manager.pause()
            } label: {
                Image(systemName: manager.state == .paused ? "play.fill" : "pause.fill")
                    .font(DS.Typography.icon(13, weight: .medium))
                    .foregroundStyle(DS.Color.textPrimary)
            }
            .buttonStyle(.plain)
            .help(manager.state == .paused ? "Resume" : "Pause")
            .accessibilityLabel(manager.state == .paused ? "Resume speaking" : "Pause speaking")

            ProgressView(value: manager.progress ?? 0)
                .frame(width: 110)
                .tint(DS.Color.accent)

            Button {
                manager.stop()
            } label: {
                Image(systemName: "stop.fill")
                    .font(DS.Typography.icon(13, weight: .medium))
                    .foregroundStyle(DS.Color.textPrimary)
            }
            .buttonStyle(.plain)
            .help("Stop speaking")
            .accessibilityLabel("Stop speaking")

            Menu {
                ForEach(Self.ratePresets, id: \.self) { rate in
                    Button {
                        speechRate = rate
                    } label: {
                        if abs(speechRate - rate) < 0.01 {
                            Label(Self.rateLabel(rate), systemImage: "checkmark")
                        } else {
                            Text(Self.rateLabel(rate))
                        }
                    }
                }
            } label: {
                Image(systemName: "speedometer")
                    .font(DS.Typography.icon(13))
                    .foregroundStyle(DS.Color.textPrimary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Speech rate")
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
        .background(.regularMaterial, in: Capsule())
        .dsShadow(DS.Shadow.float)
        .accessibilityElement(children: .contain)
    }

    private static func rateLabel(_ rate: Double) -> LocalizedStringKey {
        switch rate {
        case ..<0.45: return "Slow"
        case 0.45..<0.55: return "Normal"
        default: return "Fast"
        }
    }
}
