//
//  ShortcutsSettingsView.swift
//  boringNotch
//
//  Created by Richard Kunkli on 07/08/2024.
//

import KeyboardShortcuts
import SwiftUI

struct ShortcutsSettingsView: View {
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Toggle Notch Open:", name: .toggleNotchOpen)
            } header: {
                Text("Notch")
            }
            Section {
                KeyboardShortcuts.Recorder("Start or pause the stopwatch:", name: .focusToggleStopwatch)
                KeyboardShortcuts.Recorder("Add a marker:", name: .focusAddMarker)
                KeyboardShortcuts.Recorder("Reset the stopwatch:", name: .focusResetStopwatch)
                KeyboardShortcuts.Recorder("Start or stop recording:", name: .focusToggleRecording)
            } header: {
                Text("Focus")
            }
            Section {
                KeyboardShortcuts.Recorder("Toggle Sneak Peek:", name: .toggleSneakPeek)
            } header: {
                Text("Media")
            } footer: {
                Text(
                    "Sneak Peek shows the media title and artist under the notch for a few seconds."
                )
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
                .font(.caption)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Shortcuts")
    }
}
