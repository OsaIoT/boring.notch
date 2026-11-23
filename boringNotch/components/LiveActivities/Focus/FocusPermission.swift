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

enum FocusPermission: Equatable, Sendable {
    case camera
    case microphone

    private var mediaType: AVMediaType {
        switch self {
        case .camera: .video
        case .microphone: .audio
        }
    }

    private var settingsAnchor: String {
        switch self {
        case .camera: "Privacy_Camera"
        case .microphone: "Privacy_Microphone"
        }
    }

    /// Asks the first time; afterwards only reports the user's choice.
    func ensureAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: mediaType)
        default:
            return false
        }
    }

    @MainActor
    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(settingsAnchor)") else { return }
        NSWorkspace.shared.open(url)
    }
}
