//
//  RecordingCard.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//
//  Focus-tab controls for filming yourself while you think out loud.
//

import Defaults
import SwiftUI

struct RecordingCard: View {
    @ObservedObject private var recorder = RecordingManager.shared
    @Default(.focusRecordMicrophone) private var includeMicrophone
    @Default(.isMirrored) private var isMirrored

    static let width: CGFloat = 236

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                preview
                VStack(alignment: .leading, spacing: 6) {
                    controls
                    status
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

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.06))
            if let session = recorder.previewSession {
                CameraPreviewLayerView(session: session, isMirrored: isMirrored)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Image(systemName: "web.camera")
                    .font(.system(size: 18))
                    .foregroundStyle(.gray)
            }
        }
        .frame(width: 80, height: 60)
    }

    private var controls: some View {
        HStack(spacing: 2) {
            recordButton
            if recorder.isRecording {
                HoverButton(icon: recorder.phase == .paused ? "play.fill" : "pause.fill", iconColor: .white) {
                    recorder.togglePause()
                }
                .help(recorder.phase == .paused ? Text("Resume recording") : Text("Pause recording"))
            } else {
                HoverButton(
                    icon: includeMicrophone ? "mic.fill" : "mic.slash.fill",
                    iconColor: includeMicrophone ? .white : .gray
                ) {
                    includeMicrophone.toggle()
                }
                .disabled(recorder.isBusy)
                .help(includeMicrophone ? Text("Microphone on") : Text("Microphone off"))
            }
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
        .help(recorder.isRecording ? Text("Stop recording") : Text("Record the webcam"))
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
            statusLabel(includeMicrophone ? Text("Webcam and voice") : Text("Webcam only"), color: .gray)
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
            HStack(spacing: 4) {
                (permission == .camera ? Text("Camera access is off.") : Text("Microphone access is off."))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button {
                    permission.openSystemSettings()
                } label: {
                    Text("Settings")
                        .underline()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
            }
            .font(.system(size: 11))
        case .message(let message):
            Text(verbatim: message)
                .font(.system(size: 11))
                .foregroundStyle(.orange)
                .lineLimit(2)
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
