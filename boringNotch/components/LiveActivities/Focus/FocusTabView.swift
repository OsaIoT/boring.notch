//
//  FocusTabView.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//
//  The "Focus" tab of the open notch: stopwatch controls, and room for the
//  recording controls next to them.
//

import Defaults
import SwiftUI

struct FocusTabView: View {
    private let spacing: CGFloat = 10

    var body: some View {
        // Exactly half each, whatever the cards contain.
        GeometryReader { proxy in
            let cardWidth = max(0, (proxy.size.width - spacing) / 2)
            HStack(alignment: .top, spacing: spacing) {
                StopwatchCard()
                    .frame(width: cardWidth)
                RecordingCard()
                    .frame(width: cardWidth)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// One marker action for whatever is running: the stopwatch gets a lap and
/// the recording a timestamp in its notes file.
@MainActor
enum FocusMarker {
    static func add() {
        StopwatchManager.shared.addMarker()
        RecordingManager.shared.addMarker()
    }
}

/// The time, start/pause, reset, markers and the target picker.
struct StopwatchCard: View {
    @ObservedObject private var stopwatch = StopwatchManager.shared
    @ObservedObject private var recorder = RecordingManager.shared
    @Default(.focusTargetPresets) private var storedPresets

    /// LeetCode difficulty initials, paired with the three presets.
    private static let difficultyInitials = ["E", "M", "H"]

    var body: some View {
        let state = stopwatch.state
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                StopwatchTimeText(state: state, font: .system(size: 34, weight: .semibold, design: .rounded))
                if let target = state.target {
                    Text(verbatim: "/ " + StopwatchState.format(target))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.gray)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 2) {
                HoverButton(icon: state.isRunning ? "pause.fill" : "play.fill", iconColor: .white) {
                    stopwatch.toggle()
                }
                .help(state.isRunning ? Text("Pause") : Text("Start"))

                HoverButton(icon: "arrow.counterclockwise", iconColor: state.isActive ? .white : .gray) {
                    stopwatch.reset()
                }
                .disabled(!state.isActive)
                .help(Text("Reset"))

                let canMark = state.isActive || recorder.isRecording
                HoverButton(icon: "flag.fill", iconColor: canMark ? .white : .gray) {
                    FocusMarker.add()
                }
                .disabled(!canMark)
                .help(Text("Add marker"))

                Spacer(minLength: 8)

                targetPicker(selected: state.target)
            }

            markerStrip(state.markers)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private func targetPicker(selected: TimeInterval?) -> some View {
        let presets = StopwatchState.normalizedPresets(storedPresets)
        return HStack(spacing: 4) {
            TargetChip(isSelected: selected == nil) {
                stopwatch.setTarget(minutes: nil)
            } label: {
                Image(systemName: "infinity")
            }
            .help(Text("No target"))

            ForEach(presets.indices, id: \.self) { index in
                let minutes = presets[index]
                TargetChip(isSelected: selected == TimeInterval(minutes * 60)) {
                    stopwatch.setTarget(minutes: minutes)
                } label: {
                    Text(verbatim: "\(Self.difficultyInitials[index]) \(minutes)")
                }
                .help(Text("Target: \(minutes) min"))
            }
        }
    }

    @ViewBuilder
    private func markerStrip(_ markers: [StopwatchMarker]) -> some View {
        if markers.isEmpty {
            Text("Flag key moments with the marker button.")
                .font(.system(size: 11))
                .foregroundStyle(.gray)
                .lineLimit(1)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(markers) { marker in
                            MarkerLabel(marker: marker)
                                .id(marker.id)
                        }
                    }
                }
                .onChange(of: markers.count) { _, _ in
                    guard let last = markers.last else { return }
                    withAnimation(.smooth) {
                        proxy.scrollTo(last.id, anchor: .trailing)
                    }
                }
            }
        }
    }
}

private struct TargetChip<Label: View>: View {
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? .white : .gray)
                .padding(.horizontal, 6)
                .frame(height: 22)
                .background(Capsule().fill(Color.white.opacity(isSelected ? 0.2 : 0.07)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct MarkerLabel: View {
    let marker: StopwatchMarker

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "flag.fill")
                .font(.system(size: 8))
            Text(verbatim: "\(marker.id)  \(StopwatchState.format(marker.elapsed))")
            Text(verbatim: "+" + StopwatchState.format(marker.split))
                .foregroundStyle(.gray)
        }
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(.white.opacity(0.85))
    }
}
