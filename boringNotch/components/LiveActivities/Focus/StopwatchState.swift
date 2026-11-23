//
//  StopwatchState.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//
//  Pure model of the Focus stopwatch. All the time math lives here, away
//  from clocks and views, so it can be unit-tested and persisted as-is.
//

import Defaults
import Foundation

/// How the elapsed time compares with the optional target.
enum StopwatchTargetPhase: Equatable {
    /// No target set.
    case none
    case onTrack
    /// At least `StopwatchState.nearThreshold` of the target has elapsed.
    case near
    /// The target has been reached or passed. The stopwatch keeps counting.
    case over
}

/// A moment flagged during a session ("understood the problem",
/// "started coding", …).
struct StopwatchMarker: Codable, Equatable, Identifiable, Sendable {
    /// 1-based, in the order markers were added.
    let id: Int
    /// Stopwatch time when the marker was added.
    let elapsed: TimeInterval
    /// Time since the previous marker, or since the start for the first one.
    let split: TimeInterval
}

struct StopwatchState: Codable, Equatable, Sendable, Defaults.Serializable {
    enum Status: String, Codable, Sendable {
        case idle
        case running
        case paused
    }

    /// Fraction of the target after which the time is shown as "near".
    static let nearThreshold = 0.8

    /// LeetCode-style target presets in minutes: Easy, Medium, Hard.
    static let defaultTargetPresets = [20, 35, 50]

    /// Always three presets; missing entries fall back to the defaults.
    static func normalizedPresets(_ presets: [Int]) -> [Int] {
        defaultTargetPresets.indices.map { index in
            presets.indices.contains(index) ? presets[index] : defaultTargetPresets[index]
        }
    }

    private(set) var status: Status = .idle
    /// Wall-clock start of the running segment; nil unless running.
    private(set) var segmentStart: Date?
    /// Time banked by earlier segments, i.e. before the last pause.
    private(set) var accumulated: TimeInterval = 0
    /// Optional target duration, in seconds.
    var target: TimeInterval?
    private(set) var markers: [StopwatchMarker] = []

    var isActive: Bool { status != .idle }
    var isRunning: Bool { status == .running }

    func elapsed(at date: Date) -> TimeInterval {
        guard status == .running, let segmentStart else { return accumulated }
        return accumulated + max(0, date.timeIntervalSince(segmentStart))
    }

    func phase(at date: Date) -> StopwatchTargetPhase {
        guard let target, target > 0 else { return .none }
        let elapsed = elapsed(at: date)
        if elapsed >= target { return .over }
        if elapsed >= target * Self.nearThreshold { return .near }
        return .onTrack
    }

    /// Seconds until the target is reached; nil when there is no target, it
    /// has already passed, or the stopwatch isn't running.
    func timeUntilTarget(at date: Date) -> TimeInterval? {
        guard status == .running, let target, target > 0 else { return nil }
        let remaining = target - elapsed(at: date)
        return remaining > 0 ? remaining : nil
    }

    /// The date a running display should tick from, so each tick lands
    /// exactly when the shown second changes. Nil unless running.
    func tickOrigin() -> Date? {
        guard status == .running, let segmentStart else { return nil }
        let fraction = accumulated.truncatingRemainder(dividingBy: 1)
        return segmentStart.addingTimeInterval(-fraction)
    }

    mutating func start(at date: Date) {
        guard status != .running else { return }
        segmentStart = date
        status = .running
    }

    mutating func pause(at date: Date) {
        guard status == .running else { return }
        accumulated = elapsed(at: date)
        segmentStart = nil
        status = .paused
    }

    /// Back to zero. The target is kept: it's a choice, not session data.
    mutating func reset() {
        status = .idle
        segmentStart = nil
        accumulated = 0
        markers = []
    }

    /// Adds a marker at the current time. Ignored while idle.
    @discardableResult
    mutating func addMarker(at date: Date) -> StopwatchMarker? {
        guard isActive else { return nil }
        let now = elapsed(at: date)
        let previous = markers.last?.elapsed ?? 0
        let marker = StopwatchMarker(id: markers.count + 1, elapsed: now, split: now - previous)
        markers.append(marker)
        return marker
    }

    /// `m:ss` under an hour, `h:mm:ss` from there on.
    static func format(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return "\(hours):\(twoDigits(minutes)):\(twoDigits(seconds))"
        }
        return "\(minutes):\(twoDigits(seconds))"
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
