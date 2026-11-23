//
//  FocusSettingsView.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import AppKit
import Defaults
import KeyboardShortcuts
import SwiftUI

struct FocusSettingsView: View {
    let camera: CameraModel

    @Default(.focusTargetPresets) private var storedPresets
    @Default(.focusRecordMicrophone) private var recordMicrophone
    @Default(.focusCameraID) private var cameraID
    @Default(.focusMicrophoneID) private var microphoneID
    @Default(.focusRecordingQuality) private var quality
    @Default(.focusRecordingFolderBookmark) private var folderBookmark
    @Default(.focusDisplayID) private var displayID
    @Default(.focusBubbleSize) private var bubbleSize
    @State private var microphones: [AudioInputDevice] = []
    @State private var screens: [ScreenChoice] = []

    private struct ScreenChoice: Identifiable {
        let id: Int
        let name: String
    }

    private static let difficultyNames: [LocalizedStringKey] = ["Easy", "Medium", "Hard"]
    /// Minutes a target can be set to.
    private static let presetRange = 1...300

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .focusEnabled) {
                    Text("Show the Focus tab")
                }
                Defaults.Toggle(key: .focusShowInClosedNotch) {
                    Text("Show the stopwatch in the closed notch")
                }
            } header: {
                Text("General")
            } footer: {
                HelpText("While the stopwatch is on, the closed notch shows the elapsed time. Swipe sideways on it to switch to music.")
            }

            targetSection

            recordingSection

            if RecordingManager.canRecordScreen {
                screenSection
            }

            savingSection

            Section {
                KeyboardShortcuts.Recorder("Start or pause the stopwatch:", name: .focusToggleStopwatch)
                KeyboardShortcuts.Recorder("Add a marker:", name: .focusAddMarker)
                KeyboardShortcuts.Recorder("Reset the stopwatch:", name: .focusResetStopwatch)
                KeyboardShortcuts.Recorder("Start or stop recording:", name: .focusToggleRecording)
            } header: {
                Text("Shortcuts")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Focus")
        .onAppear {
            camera.refresh()
            microphones = CameraRecorder.availableMicrophones()
            screens = NSScreen.screens.compactMap { screen in
                screen.cgDisplayID.map { ScreenChoice(id: Int($0), name: screen.localizedName) }
            }
        }
    }

    // MARK: - Sections

    private var targetSection: some View {
        Section {
            ForEach(Self.difficultyNames.indices, id: \.self) { index in
                LabeledContent {
                    HStack(spacing: 6) {
                        TextField(value: presetBinding(index), format: .number) {
                            Text(Self.difficultyNames[index])
                        }
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 56)
                        Text("min")
                            .foregroundStyle(.secondary)
                        Stepper(value: presetBinding(index), in: Self.presetRange, step: 5) {
                            Text(Self.difficultyNames[index])
                        }
                        .labelsHidden()
                    }
                } label: {
                    Text(Self.difficultyNames[index])
                }
            }
            Defaults.Toggle(key: .focusTargetSound) {
                Text("Play a sound when the target is reached")
            }
        } header: {
            Text("Target times")
        } footer: {
            HelpText("Type the minutes or use the arrows: these are the E, M and H buttons in the Focus tab. The time turns orange at 80% of the target and red once you go over it, and the stopwatch keeps counting.")
        }
    }

    private var recordingSection: some View {
        Section {
            Picker("Camera", selection: $cameraID) {
                Text("Automatic").tag(String?.none)
                ForEach(camera.availableCameras) { device in
                    Text(device.name).tag(String?.some(device.id))
                }
            }
            Defaults.Toggle(key: .focusRecordMicrophone) {
                Text("Record the microphone")
            }
            Picker("Microphone", selection: $microphoneID) {
                Text("Automatic").tag(String?.none)
                ForEach(microphones) { microphone in
                    Text(microphone.name).tag(String?.some(microphone.id))
                }
            }
            .disabled(!recordMicrophone)
            Picker("Quality", selection: $quality) {
                Text(verbatim: "1080p").tag(RecordingQuality.hd1080)
                Text(verbatim: "720p").tag(RecordingQuality.hd720)
            }
        } header: {
            Text("Recording")
        } footer: {
            HelpText("Automatic uses the Mac's built-in camera first, so an iPhone nearby isn't picked by mistake.")
        }
    }

    private var screenSection: some View {
        Section {
            Picker("Screen to record", selection: $displayID) {
                Text("The one with the pointer").tag(Int?.none)
                ForEach(screens) { screen in
                    Text(verbatim: screen.name).tag(Int?.some(screen.id))
                }
            }
            Defaults.Toggle(key: .focusShowClicks) {
                Text("Highlight clicks")
            }
            Defaults.Toggle(key: .hideFromScreenRecording) {
                Text("Hide the notch in screen recordings")
            }
            Picker("Webcam bubble", selection: $bubbleSize) {
                Text("Compact").tag(BubbleSize.small)
                Text("Regular").tag(BubbleSize.medium)
                Text("Large").tag(BubbleSize.large)
            }
            Defaults.Toggle(key: .focusBubbleInCameraMode) {
                Text("Show the bubble when recording only the webcam")
            }
        } header: {
            Text("Screen")
        } footer: {
            HelpText("With webcam and screen on together, a round bubble with your webcam floats on screen and ends up in the video. Drag it where you like: it remembers the spot. Screen recordings can't be paused.")
        }
    }

    private var savingSection: some View {
        Section {
            LabeledContent {
                HStack(spacing: 8) {
                    Text(verbatim: RecordingLibrary.displayPath(for: folderBookmark))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Button("Change…") {
                        chooseFolder()
                    }
                    if folderBookmark != nil {
                        Button("Default") {
                            folderBookmark = nil
                        }
                    }
                }
            } label: {
                Text("Folder")
            }
            Defaults.Toggle(key: .focusAddRecordingsToShelf) {
                Text("Add finished videos to the Shelf")
            }
            Defaults.Toggle(key: .focusOpenRecordingWhenDone) {
                Text("Open the video when the recording ends")
            }
        } header: {
            Text("Saving")
        } footer: {
            HelpText("If you add markers while recording, a .md file with their times in the video is saved next to it.")
        }
    }

    // MARK: - Helpers

    private var presets: [Int] {
        StopwatchState.normalizedPresets(storedPresets)
    }

    private func presetBinding(_ index: Int) -> Binding<Int> {
        Binding(
            get: { presets[index] },
            set: { newValue in
                let clamped = min(max(newValue, Self.presetRange.lowerBound), Self.presetRange.upperBound)
                let previous = presets[index]
                var updated = presets
                updated[index] = clamped
                storedPresets = updated
                // A session already using this preset follows the new value.
                let stopwatch = StopwatchManager.shared
                if stopwatch.state.target == TimeInterval(previous * 60) {
                    stopwatch.setTarget(minutes: clamped)
                }
            }
        )
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Choose")
        panel.message = String(localized: "Choose where Focus recordings are saved.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            folderBookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            Log.general.error("Could not remember the Focus recording folder: \(error.localizedDescription, privacy: .public)")
        }
    }
}
