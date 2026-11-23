//
//  FocusLiveActivity.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//
//  Closed-notch pill for Focus: a status icon left of the hardware notch
//  (stopwatch, or the red recording dot), the elapsed time right of it.
//

import Defaults
import SwiftUI

struct FocusLiveActivity: View {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var stopwatch = StopwatchManager.shared
    @ObservedObject private var recorder = RecordingManager.shared
    @Default(.focusShowInClosedNotch) private var showsStopwatch

    /// Width of each side of the pill, sized for `1:02:03`. Both sides must
    /// match, otherwise the black centre drifts off the physical notch.
    static let sideWidth: CGFloat = 52

    /// The stopwatch when it's shown, otherwise the recording's own clock.
    private var displayedClock: StopwatchState {
        showsStopwatch && stopwatch.isActive ? stopwatch.state : recorder.clock
    }

    private var showsRecordingClock: Bool {
        !(showsStopwatch && stopwatch.isActive)
    }

    var body: some View {
        let clock = displayedClock
        TimelineView(clock.displaySchedule) { context in
            let date = context.date.addingTimeInterval(StopwatchState.tickEpsilon)
            HStack(spacing: 0) {
                statusIcon(tint: clock.tint(at: date))
                    .padding(.leading, 4)
                    .frame(width: Self.sideWidth, alignment: .leading)

                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width - 4 + 2 * liveActivityEdgeMargin)

                Text(verbatim: StopwatchState.format(clock.elapsed(at: date)))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(timeTint(clock: clock, date: date))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.trailing, 2)
                    .frame(width: Self.sideWidth, alignment: .trailing)
            }
        }
        .frame(height: vm.effectiveClosedNotchHeight)
        .sensoryFeedback(trigger: stopwatch.targetReachedCount) { _, _ in
            Defaults[.enableHaptics] ? .levelChange : nil
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(recorder.isRecording ? Text("Recording") : Text("Stopwatch"))
    }

    @ViewBuilder
    private func statusIcon(tint: Color) -> some View {
        switch recorder.phase {
        case .starting, .recording:
            Image(systemName: "circle.fill")
                .font(.system(size: 9))
                .foregroundStyle(.red)
                .symbolEffect(.pulse, options: .repeating, isActive: recorder.phase == .recording)
        case .paused:
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.red)
        case .finishing:
            ProgressView()
                .controlSize(.mini)
        case .saved:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.orange)
        case .idle:
            Image(systemName: stopwatch.isRunning ? "stopwatch" : "pause.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .symbolEffect(.bounce, value: stopwatch.targetReachedCount)
        }
    }

    private func timeTint(clock: StopwatchState, date: Date) -> Color {
        guard showsRecordingClock else { return clock.tint(at: date) }
        switch recorder.phase {
        case .saved: return .green
        case .failed: return .orange
        case .recording: return .white
        default: return .gray
        }
    }
}
