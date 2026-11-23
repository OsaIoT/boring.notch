//
//  ShortcutConstants.swift
//  boringNotch
//
//  Created by Richard Kunkli on 16/08/2024.
//

import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let toggleSneakPeek = Self("toggleSneakPeek", initial: .init(.h, modifiers: [.command, .shift]))
    static let toggleNotchOpen = Self("toggleNotchOpen", initial: .init(.i, modifiers: [.command, .shift]))

    // MARK: Focus
    static let focusToggleStopwatch = Self("focusToggleStopwatch", initial: .init(.t, modifiers: [.control, .option, .command]))
    static let focusAddMarker = Self("focusAddMarker", initial: .init(.m, modifiers: [.control, .option, .command]))
    static let focusResetStopwatch = Self("focusResetStopwatch")
    static let focusToggleRecording = Self("focusToggleRecording", initial: .init(.r, modifiers: [.control, .option, .command]))
}
