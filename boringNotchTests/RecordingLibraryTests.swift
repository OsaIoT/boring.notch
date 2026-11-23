//
//  RecordingLibraryTests.swift
//  boringNotchTests
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import XCTest

@testable import boringNotch

final class RecordingLibraryTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
        return calendar
    }

    /// 23 November 2026, 21:05 in Rome.
    private var sessionDate: Date {
        DateComponents(calendar: calendar, year: 2026, month: 11, day: 23, hour: 21, minute: 5).date ?? Date()
    }

    func testTimestampSortsAndAvoidsColons() {
        XCTAssertEqual(RecordingLibrary.timestamp(sessionDate, calendar: calendar), "2026-11-23 21.05")
    }

    func testMovieURLUsesDateAndSource() {
        let folder = URL(fileURLWithPath: "/tmp/focus", isDirectory: true)
        let url = RecordingLibrary.movieURL(in: folder, source: .camera, date: sessionDate, calendar: calendar) { _ in false }
        XCTAssertEqual(url.deletingLastPathComponent().path, "/tmp/focus")
        XCTAssertEqual(url.pathExtension, "mov")
        XCTAssertTrue(url.lastPathComponent.hasPrefix("2026-11-23 21.05 "))
    }

    func testMovieURLNeverOverwritesAnExistingFile() {
        let folder = URL(fileURLWithPath: "/tmp/focus", isDirectory: true)
        let first = RecordingLibrary.movieURL(in: folder, source: .camera, date: sessionDate, calendar: calendar) { _ in false }
        let taken: Set<String> = [first.path, first.path.replacingOccurrences(of: ".mov", with: " (2).mov")]

        let next = RecordingLibrary.movieURL(in: folder, source: .camera, date: sessionDate, calendar: calendar) {
            taken.contains($0.path)
        }
        XCTAssertTrue(next.lastPathComponent.hasSuffix(" (3).mov"), next.lastPathComponent)
    }

    func testMarkersFileSitsNextToTheVideo() {
        let movie = URL(fileURLWithPath: "/tmp/focus/2026-11-23 21.05 Webcam.mov")
        XCTAssertEqual(RecordingLibrary.markersURL(for: movie).lastPathComponent, "2026-11-23 21.05 Webcam.md")
    }

    func testClockAlwaysShowsHours() {
        XCTAssertEqual(RecordingLibrary.clock(0), "00:00:00")
        XCTAssertEqual(RecordingLibrary.clock(465.9), "00:07:45")
        XCTAssertEqual(RecordingLibrary.clock(3723), "01:02:03")
    }

    func testMarkersDocumentListsEveryMarker() {
        let document = RecordingLibrary.markersDocument(
            title: "2026-11-23 21.05 Webcam",
            duration: 1421,
            markers: [RecordingMarker(index: 1, time: 130), RecordingMarker(index: 2, time: 465)]
        )
        XCTAssertTrue(document.hasPrefix("# 2026-11-23 21.05 Webcam\n"))
        XCTAssertTrue(document.contains("23:41"), "Duration in stopwatch format")
        XCTAssertTrue(document.contains("- 00:02:10 — Marker 1"))
        XCTAssertTrue(document.contains("- 00:07:45 — Marker 2"))
        XCTAssertTrue(document.hasSuffix("\n"))
    }

    func testDefaultFolderIsInTheRealMoviesFolder() {
        let folder = RecordingLibrary.defaultFolder
        XCTAssertEqual(folder.lastPathComponent, "Boring Notch")
        XCTAssertEqual(folder.deletingLastPathComponent().lastPathComponent, "Movies")
        XCTAssertFalse(folder.path.contains("/Library/Containers/"), "Must not point inside the sandbox container")
    }
}
