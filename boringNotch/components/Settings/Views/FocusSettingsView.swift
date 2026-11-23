//
//  FocusSettingsView.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//

import Defaults
import KeyboardShortcuts
import SwiftUI

struct FocusSettingsView: View {
    @Default(.focusTargetPresets) private var storedPresets

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

            Section {
                KeyboardShortcuts.Recorder("Start or pause the stopwatch:", name: .focusToggleStopwatch)
                KeyboardShortcuts.Recorder("Add a marker:", name: .focusAddMarker)
                KeyboardShortcuts.Recorder("Reset the stopwatch:", name: .focusResetStopwatch)
            } header: {
                Text("Shortcuts")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Focus")
    }

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
}
