//
//  RecordingCard.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//
//  Focus-tab controls for recording yourself while you think out loud:
//  webcam, screen, or both (with the webcam bubble).
//

import Defaults
import SwiftUI

struct RecordingCard: View {
    @ObservedObject private var recorder = RecordingManager.shared
    @Default(.focusRecordMicrophone) private var includeMicrophone
    @Default(.focusRecordCamera) private var recordCamera
    @Default(.focusRecordScreen) private var recordScreen

    static let width: CGFloat = 236

    private var recordsScreen: Bool { recordScreen && RecordingManager.canRecordScreen }

    /// The recording in progress, or the one the toggles describe.
    private var displayedSource: RecordingSource {
        if recorder.isBusy, let active = recorder.activeSource {
            return active
        }
        return RecordingSource(camera: recordCamera, screen: recordsScreen) ?? .camera
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                preview
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        recordButton
                        status
                    }
                    secondaryControls
                }
                Spacer(minLength: 0)
            }
            footer
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: Self.width, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    // MARK: - Pieces

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.06))
            if let previewLayer = recorder.previewLayer {
                HostedLayerView(hostedLayer: previewLayer)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Image(systemName: placeholderSymbol)
                    .font(.system(size: 18))
                    .foregroundStyle(.gray)
            }
        }
        .frame(width: 76, height: 57)
    }

    private var placeholderSymbol: String {
        switch displayedSource {
        case .camera: "web.camera"
        case .screen: "display"
        case .screenAndCamera: "pip"
        }
    }

    private var recordButton: some View {
        Button {
            recorder.toggle()
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(Color.white.opacity(0.85), lineWidth: 2)
                    .frame(width: 26, height: 26)
                if recorder.isRecording {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                } else {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 18, height: 18)
                }
            }
            .frame(width: 30, height: 30)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(recorder.phase == .starting || recorder.phase == .finishing)
        .help(recorder.isRecording ? Text("Stop recording") : Text("Start recording"))
    }

    @ViewBuilder
    private var status: some View {
        switch recorder.phase {
        case .recording, .paused:
            StopwatchTimeText(state: recorder.clock, font: .system(size: 15, weight: .semibold, design: .rounded))
        case .starting:
            statusLabel(Text("Starting…"), color: .gray)
        case .finishing:
            statusLabel(Text("Saving…"), color: .gray)
        case .saved:
            statusLabel(Text("Saved"), systemImage: "checkmark.circle.fill", color: .green)
        case .failed:
            statusLabel(Text("Not recorded"), systemImage: "exclamationmark.triangle.fill", color: .orange)
        case .idle:
            statusLabel(sourceName, color: .gray)
        }
    }

    private var sourceName: Text {
        switch displayedSource {
        case .camera: Text("Webcam")
        case .screen: Text("Screen")
        case .screenAndCamera: Text("Screen + webcam")
        }
    }

    @ViewBuilder
    private var secondaryControls: some View {
        if recorder.isRecording {
            if recorder.canPause {
                HoverButton(icon: recorder.phase == .paused ? "play.fill" : "pause.fill", iconColor: .white) {
                    recorder.togglePause()
                }
                .help(recorder.phase == .paused ? Text("Resume recording") : Text("Pause recording"))
            } else {
                Text("Screen recordings can't be paused.")
                    .font(.system(size: 10))
                    .foregroundStyle(.gray)
                    .lineLimit(2)
            }
        } else {
            HStack(spacing: 4) {
                SourceToggle(symbol: "web.camera", isOn: recordCamera, help: Text("Webcam")) {
                    recordCamera.toggle()
                }
                // At least one of webcam and screen stays on.
                .disabled(recorder.isBusy || (recordCamera && !recordsScreen))

                if RecordingManager.canRecordScreen {
                    SourceToggle(symbol: "display", isOn: recordScreen, help: Text("Screen")) {
                        recordScreen.toggle()
                    }
                    .disabled(recorder.isBusy || (recordScreen && !recordCamera))
                }

                SourceToggle(
                    symbol: includeMicrophone ? "mic.fill" : "mic.slash.fill",
                    isOn: includeMicrophone,
                    help: includeMicrophone ? Text("Microphone on") : Text("Microphone off")
                ) {
                    includeMicrophone.toggle()
                }
                .disabled(recorder.isBusy)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if case .failed(let failure) = recorder.phase {
            failureFooter(failure)
        } else if let url = recorder.lastRecording {
            HStack(spacing: 4) {
                Text(verbatim: url.deletingPathExtension().lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.gray)
                Spacer(minLength: 4)
                footerButton("play.rectangle.fill", help: Text("Open the video")) {
                    recorder.openLastRecording()
                }
                footerButton("folder.fill", help: Text("Show in Finder")) {
                    recorder.revealLastRecording()
                }
            }
            .font(.system(size: 11))
        } else {
            Text("Film yourself while you think out loud.")
                .font(.system(size: 11))
                .foregroundStyle(.gray)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func failureFooter(_ failure: RecordingManager.Failure) -> some View {
        switch failure {
        case .permission(let permission):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                permissionMessage(permission)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                Spacer(minLength: 4)
                linkButton(Text("Settings")) {
                    permission.openSystemSettings()
                }
                if permission == .screen {
                    linkButton(Text("Restart")) {
                        ApplicationRelauncher.restart()
                    }
                }
            }
            .font(.system(size: 11))
        case .noSource:
            Text("Choose the webcam, the screen or both.")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
        case .message(let message):
            Text(verbatim: message)
                .font(.system(size: 11))
                .foregroundStyle(.orange)
                .lineLimit(2)
        }
    }

    private func permissionMessage(_ permission: FocusPermission) -> Text {
        switch permission {
        case .camera: Text("Camera access is off.")
        case .microphone: Text("Microphone access is off.")
        case .screen: Text("Allow screen recording, then restart.")
        }
    }

    private func statusLabel(_ text: Text, systemImage: String? = nil, color: Color) -> some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            text
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(color)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private func linkButton(_ title: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            title.underline()
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    private func footerButton(_ systemImage: String, help: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 20, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// A small on/off button for one recording source.
private struct SourceToggle: View {
    let symbol: String
    let isOn: Bool
    let help: Text
    let action: () -> Void

    @Environment(\.isEnabled) var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isOn ? Color.white : Color.gray)
                .frame(width: 28, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(isOn ? 0.18 : 0.05))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.55)
        .help(help)
    }
}
