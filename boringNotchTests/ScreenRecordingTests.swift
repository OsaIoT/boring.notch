//
//  ScreenRecordingTests.swift
//  boringNotchTests
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import XCTest

@testable import boringNotch

final class ScreenRecordingTests: XCTestCase {
    func testTogglesMapToTheRecordingSource() {
        XCTAssertEqual(RecordingSource(camera: true, screen: false), .camera)
        XCTAssertEqual(RecordingSource(camera: false, screen: true), .screen)
        XCTAssertEqual(RecordingSource(camera: true, screen: true), .screenAndCamera)
        XCTAssertNil(RecordingSource(camera: false, screen: false))
    }

    func testSourcesKnowWhatTheyUse() {
        XCTAssertTrue(RecordingSource.camera.usesCamera)
        XCTAssertFalse(RecordingSource.camera.usesScreen)
        XCTAssertFalse(RecordingSource.screen.usesCamera)
        XCTAssertTrue(RecordingSource.screen.usesScreen)
        XCTAssertTrue(RecordingSource.screenAndCamera.usesCamera)
        XCTAssertTrue(RecordingSource.screenAndCamera.usesScreen)
    }

    func testRetinaScreenIsScaledDownToTheQualityLimit() {
        // 14" MacBook Pro panel.
        let size = ScreenCaptureSize.outputSize(pixelWidth: 3024, pixelHeight: 1964, quality: .hd1080)
        XCTAssertLessThanOrEqual(size.height, 1440)
        XCTAssertGreaterThan(size.height, 1400)
        XCTAssertEqual(Double(size.width) / Double(size.height), 3024.0 / 1964.0, accuracy: 0.01)
        XCTAssertEqual(size.width % 2, 0)
        XCTAssertEqual(size.height % 2, 0)

        let smaller = ScreenCaptureSize.outputSize(pixelWidth: 3024, pixelHeight: 1964, quality: .hd720)
        XCTAssertLessThanOrEqual(smaller.height, 900)
    }

    func testSmallScreensAreNeverUpscaled() {
        let size = ScreenCaptureSize.outputSize(pixelWidth: 1920, pixelHeight: 1080, quality: .hd1080)
        XCTAssertEqual(size.width, 1920)
        XCTAssertEqual(size.height, 1080)
    }

    func testOddSizesBecomeEven() {
        let size = ScreenCaptureSize.outputSize(pixelWidth: 1281, pixelHeight: 801, quality: .hd1080)
        XCTAssertEqual(size.width, 1280)
        XCTAssertEqual(size.height, 800)
    }
}
