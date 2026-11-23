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
                    Stepper(value: presetBinding(index), in: 5...180, step: 5) {
                        HStack {
                            Text(Self.difficultyNames[index])
                            Spacer()
                            Text("\(presets[index]) min")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Defaults.Toggle(key: .focusTargetSound) {
                    Text("Play a sound when the target is reached")
                }
            } header: {
                Text("Target times")
            } footer: {
                HelpText("The time turns orange at 80% of the target and red once you go over it. The stopwatch keeps counting.")
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
                var updated = presets
                updated[index] = newValue
                storedPresets = updated
            }
        )
    }
}
