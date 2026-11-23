//
//  FocusLiveActivity.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//
//  Closed-notch pill for the Focus stopwatch: an icon left of the hardware
//  notch, the elapsed time right of it.
//

import Defaults
import SwiftUI

struct FocusLiveActivity: View {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var stopwatch = StopwatchManager.shared

    /// Width of each side of the pill, sized for `1:02:03`. Both sides must
    /// match, otherwise the black centre drifts off the physical notch.
    static let sideWidth: CGFloat = 52

    var body: some View {
        let state = stopwatch.state
        TimelineView(state.displaySchedule) { context in
            let date = context.date.addingTimeInterval(StopwatchState.tickEpsilon)
            let tint = state.tint(at: date)
            HStack(spacing: 0) {
                Image(systemName: state.isRunning ? "stopwatch" : "pause.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .symbolEffect(.bounce, value: stopwatch.targetReachedCount)
                    .padding(.leading, 4)
                    .frame(width: Self.sideWidth, alignment: .leading)

                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width - 4 + 2 * liveActivityEdgeMargin)

                Text(verbatim: StopwatchState.format(state.elapsed(at: date)))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
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
        .accessibilityLabel(Text("Stopwatch"))
    }
}
