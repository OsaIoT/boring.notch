//
//  FocusPermission.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//
//  The privacy permissions Focus recordings need, and the way back to
//  System Settings when one was refused.
//

import AVFoundation
import AppKit
import CoreGraphics

enum FocusPermission: Equatable, Sendable {
    case camera
    case microphone
    case screen

    private var settingsAnchor: String {
        switch self {
        case .camera: "Privacy_Camera"
        case .microphone: "Privacy_Microphone"
        case .screen: "Privacy_ScreenCapture"
        }
    }

    /// Asks the first time; afterwards only reports the user's choice.
    func ensureAccess() async -> Bool {
        switch self {
        case .camera:
            return await Self.ensureCaptureAccess(for: .video)
        case .microphone:
            return await Self.ensureCaptureAccess(for: .audio)
        case .screen:
            if CGPreflightScreenCaptureAccess() {
                return true
            }
            // Shows the system prompt the first time and lists the app in
            // System Settings; access only takes effect after a relaunch.
            return CGRequestScreenCaptureAccess()
        }
    }

    @MainActor
    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(settingsAnchor)") else { return }
        NSWorkspace.shared.open(url)
    }

    private static func ensureCaptureAccess(for mediaType: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: mediaType)
        default:
            return false
        }
    }
}
