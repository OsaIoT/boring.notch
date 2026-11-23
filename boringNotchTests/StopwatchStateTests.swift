//
//  StopwatchStateTests.swift
//  boringNotchTests
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import XCTest

@testable import boringNotch

final class StopwatchStateTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testIdleStopwatchHasNoElapsedTime() {
        let state = StopwatchState()
        XCTAssertEqual(state.status, .idle)
        XCTAssertFalse(state.isActive)
        XCTAssertEqual(state.elapsed(at: t0), 0)
        XCTAssertNil(state.tickOrigin())
    }

    func testRunningElapsedFollowsTheClock() {
        var state = StopwatchState()
        state.start(at: t0)
        XCTAssertTrue(state.isRunning)
        XCTAssertEqual(state.elapsed(at: t0.addingTimeInterval(42)), 42, accuracy: 0.001)
        // A clock that goes backwards never yields negative time.
        XCTAssertEqual(state.elapsed(at: t0.addingTimeInterval(-5)), 0)
    }

    func testPauseFreezesAndResumeAccumulates() {
        var state = StopwatchState()
        state.start(at: t0)
        state.pause(at: t0.addingTimeInterval(10))
        XCTAssertEqual(state.status, .paused)
        XCTAssertEqual(state.elapsed(at: t0.addingTimeInterval(500)), 10, accuracy: 0.001)

        state.start(at: t0.addingTimeInterval(100))
        XCTAssertEqual(state.elapsed(at: t0.addingTimeInterval(105)), 15, accuracy: 0.001)
    }

    func testStartingTwiceKeepsTheOriginalStart() {
        var state = StopwatchState()
        state.start(at: t0)
        state.start(at: t0.addingTimeInterval(30))
        XCTAssertEqual(state.elapsed(at: t0.addingTimeInterval(60)), 60, accuracy: 0.001)
    }

    func testResetClearsTimeAndMarkersButKeepsTarget() {
        var state = StopwatchState()
        state.target = 1200
        state.start(at: t0)
        state.addMarker(at: t0.addingTimeInterval(5))
        state.reset()
        XCTAssertEqual(state.status, .idle)
        XCTAssertEqual(state.elapsed(at: t0.addingTimeInterval(99)), 0)
        XCTAssertTrue(state.markers.isEmpty)
        XCTAssertEqual(state.target, 1200)
    }

    func testMarkersRecordElapsedAndSplit() {
        var state = StopwatchState()
        XCTAssertNil(state.addMarker(at: t0), "Markers are ignored while idle")

        state.start(at: t0)
        state.addMarker(at: t0.addingTimeInterval(65))
        state.addMarker(at: t0.addingTimeInterval(200))

        XCTAssertEqual(state.markers.map(\.id), [1, 2])
        XCTAssertEqual(state.markers[0].elapsed, 65, accuracy: 0.001)
        XCTAssertEqual(state.markers[0].split, 65, accuracy: 0.001)
        XCTAssertEqual(state.markers[1].elapsed, 200, accuracy: 0.001)
        XCTAssertEqual(state.markers[1].split, 135, accuracy: 0.001)
    }

    func testTargetPhases() {
        var state = StopwatchState()
        state.start(at: t0)
        XCTAssertEqual(state.phase(at: t0.addingTimeInterval(10)), .none)

        state.target = 100
        XCTAssertEqual(state.phase(at: t0.addingTimeInterval(79)), .onTrack)
        XCTAssertEqual(state.phase(at: t0.addingTimeInterval(80)), .near)
        XCTAssertEqual(state.phase(at: t0.addingTimeInterval(100)), .over)
        XCTAssertEqual(state.phase(at: t0.addingTimeInterval(1000)), .over)
    }

    func testTimeUntilTarget() {
        var state = StopwatchState()
        state.target = 60
        XCTAssertNil(state.timeUntilTarget(at: t0), "Not running")

        state.start(at: t0)
        XCTAssertEqual(state.timeUntilTarget(at: t0.addingTimeInterval(20)) ?? -1, 40, accuracy: 0.001)
        XCTAssertNil(state.timeUntilTarget(at: t0.addingTimeInterval(60)), "Already reached")
    }

    func testTickOriginAlignsToWholeSeconds() throws {
        var state = StopwatchState()
        state.start(at: t0)
        state.pause(at: t0.addingTimeInterval(2.25))
        state.start(at: t0.addingTimeInterval(10))

        let origin = try XCTUnwrap(state.tickOrigin())
        // Elapsed at the origin plus whole seconds is always a whole number.
        let elapsed = state.elapsed(at: origin.addingTimeInterval(3))
        XCTAssertEqual(elapsed, elapsed.rounded(), accuracy: 0.0001)
    }

    func testFormat() {
        XCTAssertEqual(StopwatchState.format(0), "0:00")
        XCTAssertEqual(StopwatchState.format(5.9), "0:05")
        XCTAssertEqual(StopwatchState.format(65), "1:05")
        XCTAssertEqual(StopwatchState.format(600), "10:00")
        XCTAssertEqual(StopwatchState.format(3723), "1:02:03")
        XCTAssertEqual(StopwatchState.format(-3), "0:00")
    }

    func testNormalizedPresetsAlwaysHasThreeEntries() {
        XCTAssertEqual(StopwatchState.normalizedPresets([]), [20, 35, 50])
        XCTAssertEqual(StopwatchState.normalizedPresets([15]), [15, 35, 50])
        XCTAssertEqual(StopwatchState.normalizedPresets([10, 20, 30, 40]), [10, 20, 30])
    }

    func testCodableRoundTripKeepsARunningStopwatch() throws {
        var state = StopwatchState()
        state.target = 2100
        state.start(at: t0)
        state.addMarker(at: t0.addingTimeInterval(30))

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(StopwatchState.self, from: data)

        XCTAssertEqual(decoded, state)
        XCTAssertEqual(decoded.elapsed(at: t0.addingTimeInterval(90)), 90, accuracy: 0.001)
    }
}
