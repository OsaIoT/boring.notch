//
//  StopwatchManager.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//
//  Owns the Focus stopwatch: start/pause/reset, markers, persistence across
//  relaunches and the one-shot "target reached" signal.
//

import AppKit
import Defaults
import Foundation

@MainActor
final class StopwatchManager: ObservableObject {
    static let shared = StopwatchManager()

    /// Saved on every change, so a running stopwatch survives a relaunch:
    /// elapsed time is derived from the wall clock, not from a ticking timer.
    @Published private(set) var state: StopwatchState {
        didSet { Defaults[.focusStopwatchState] = state }
    }

    /// Bumped each time a running stopwatch crosses its target, so views can
    /// pulse once.
    @Published private(set) var targetReachedCount = 0

    private var targetTask: Task<Void, Never>?

    var isActive: Bool { state.isActive }
    var isRunning: Bool { state.isRunning }

    private init() {
        state = Defaults[.focusStopwatchState]
        scheduleTargetSignal()
    }

    func toggle() {
        if state.isRunning {
            pause()
        } else {
            start()
        }
    }

    func start() {
        state.start(at: Date())
        scheduleTargetSignal()
    }

    func pause() {
        state.pause(at: Date())
        scheduleTargetSignal()
    }

    func reset() {
        state.reset()
        scheduleTargetSignal()
    }

    func addMarker() {
        state.addMarker(at: Date())
    }

    /// Nil clears the target.
    func setTarget(minutes: Int?) {
        state.target = minutes.map { TimeInterval($0 * 60) }
        scheduleTargetSignal()
    }

    private func scheduleTargetSignal() {
        targetTask?.cancel()
        targetTask = nil
        guard let remaining = state.timeUntilTarget(at: Date()) else { return }
        targetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            self?.targetReached()
        }
    }

    private func targetReached() {
        targetReachedCount += 1
        Log.general.info("Focus stopwatch reached its target")
        if Defaults[.focusTargetSound] {
            NSSound(named: "Glass")?.play()
        }
    }
}
