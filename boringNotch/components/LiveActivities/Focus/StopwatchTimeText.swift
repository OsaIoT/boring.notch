//
//  StopwatchTimeText.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//
//  Display helpers shared by the closed-notch pill and the Focus tab.
//

import SwiftUI

extension StopwatchState {
    /// While running, ticks once a second aligned to the stopwatch, so the
    /// shown second flips exactly on time. Stopped, nothing changes, so it
    /// only ticks hourly.
    var displaySchedule: PeriodicTimelineSchedule {
        if let origin = tickOrigin() {
            return .periodic(from: origin, by: 1)
        }
        return .periodic(from: Date(), by: 3600)
    }

    /// Nudge past each tick so floating-point rounding never shows the
    /// previous second.
    static let tickEpsilon: TimeInterval = 0.05

    /// White on track, orange near the target, red past it, grey when paused.
    func tint(at date: Date) -> Color {
        guard isRunning else { return .gray }
        switch phase(at: date) {
        case .none, .onTrack: return .white
        case .near: return .orange
        case .over: return .red
        }
    }
}

/// The stopwatch time, ticking while running and tinted against the target.
struct StopwatchTimeText: View {
    let state: StopwatchState
    let font: Font

    var body: some View {
        TimelineView(state.displaySchedule) { context in
            let date = context.date.addingTimeInterval(StopwatchState.tickEpsilon)
            Text(verbatim: StopwatchState.format(state.elapsed(at: date)))
                .font(font)
                .monospacedDigit()
                .foregroundStyle(state.tint(at: date))
        }
    }
}
