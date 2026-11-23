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

    /// The recording in progress, or the one the mode picker describes.
    private var displayedSource: RecordingSource {
        if recorder.isBusy, let active = recorder.activeSource {
            return active
        }
        return RecordingSource(camera: recordCamera, screen: recordScreen && RecordingManager.canRecordScreen) ?? .camera
    }

    private var modeBinding: Binding<RecordingSource> {
        Binding(
            get: { displayedSource },
            set: { source in
                recordCamera = source.usesCamera
                recordScreen = source.usesScreen
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 10) {
                preview
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        recordButton
                        status
                    }
                    secondaryControl
                }
                Spacer(minLength: 0)
            }
            if RecordingManager.canRecordScreen {
                RecordingModePicker(selection: modeBinding)
                    .disabled(recorder.isBusy)
            }
            footer
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                Image(systemName: displayedSource.symbol)
                    .font(.system(size: 18))
                    .foregroundStyle(.gray)
            }
        }
        .frame(width: 72, height: 54)
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
            statusLabel(Text("Record"), color: .white)
        }
    }

    /// Microphone switch before recording; pause during webcam recordings.
    @ViewBuilder
    private var secondaryControl: some View {
        if recorder.isRecording {
            if recorder.canPause {
                PillButton(
                    symbol: recorder.phase == .paused ? "play.fill" : "pause.fill",
                    title: recorder.phase == .paused ? Text("Resume") : Text("Pause"),
                    isOn: true
                ) {
                    recorder.togglePause()
                }
            } else {
                Text("Screen recordings can't be paused.")
                    .font(.system(size: 10))
                    .foregroundStyle(.gray)
                    .lineLimit(2)
            }
        } else {
            PillButton(
                symbol: includeMicrophone ? "mic.fill" : "mic.slash.fill",
                title: includeMicrophone ? Text("Microphone") : Text("Muted"),
                isOn: includeMicrophone
            ) {
                includeMicrophone.toggle()
            }
            .disabled(recorder.isBusy)
            .help(includeMicrophone ? Text("Your voice is recorded. Click to mute.") : Text("Your voice isn't recorded. Click to turn the microphone on."))
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

private extension RecordingSource {
    var symbol: String {
        switch self {
        case .camera: "web.camera"
        case .screen: "display"
        case .screenAndCamera: "pip"
        }
    }
}

/// Webcam | Screen | Both: one choice, spelled out.
private struct RecordingModePicker: View {
    @Binding var selection: RecordingSource

    @Environment(\.isEnabled) var isEnabled

    var body: some View {
        HStack(spacing: 2) {
            segment(.camera, title: Text("Webcam"))
            segment(.screen, title: Text("Screen"))
            segment(.screenAndCamera, title: Text("Both"))
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .opacity(isEnabled ? 1 : 0.6)
    }

    private func segment(_ source: RecordingSource, title: Text) -> some View {
        let isSelected = selection == source
        return Button {
            withAnimation(.smooth(duration: 0.2)) {
                selection = source
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: source.symbol)
                    .font(.system(size: 10, weight: .semibold))
                title
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(isSelected ? Color.white : Color.gray)
            .frame(maxWidth: .infinity)
            .frame(height: 22)
            .background(Capsule().fill(isSelected ? Color.white.opacity(0.18) : Color.clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// A small labelled switch, clearer than a bare icon.
private struct PillButton: View {
    let symbol: String
    let title: Text
    let isOn: Bool
    let action: () -> Void

    @Environment(\.isEnabled) var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                title
                    .lineLimit(1)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(isOn ? Color.white : Color.gray)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Capsule().fill(Color.white.opacity(isOn ? 0.16 : 0.06)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.6)
    }
}
