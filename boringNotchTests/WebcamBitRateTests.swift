//
//  WebcamBitRateTests.swift
//  boringNotchTests
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import XCTest

@testable import boringNotch

final class WebcamBitRateTests: XCTestCase {
    func testFullHDWebcamIsAboutFourAndAHalfMegabits() {
        let bitRate = WebcamBitRate.average(width: 1920, height: 1080, isHEVC: true)
        XCTAssertEqual(Double(bitRate) / 1_000_000, 4.5, accuracy: 0.1)
        // About 2 GB for an hour of video.
        let gigabytesPerHour = Double(bitRate) * 3600 / 8 / 1_000_000_000
        XCTAssertEqual(gigabytesPerHour, 2.0, accuracy: 0.1)
    }

    func testLowerResolutionScalesDown() {
        let fullHD = WebcamBitRate.average(width: 1920, height: 1080, isHEVC: true)
        let hd = WebcamBitRate.average(width: 1280, height: 720, isHEVC: true)
        XCTAssertEqual(Double(hd) / 1_000_000, 2.0, accuracy: 0.1)
        XCTAssertLessThan(hd, fullHD)
    }

    func testH264GetsMoreBitsForTheSameQuality() {
        let hevc = WebcamBitRate.average(width: 1920, height: 1080, isHEVC: true)
        let h264 = WebcamBitRate.average(width: 1920, height: 1080, isHEVC: false)
        XCTAssertEqual(Double(h264) / Double(hevc), 1.6, accuracy: 0.01)
    }
}
