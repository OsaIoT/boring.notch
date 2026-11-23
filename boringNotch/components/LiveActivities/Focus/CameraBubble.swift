//
//  CameraBubble.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//
//  The floating webcam circle shown during screen recordings. It's an
//  ordinary on-screen window, so the screen recording picks it up and the
//  result is a single video with you in the corner. Drag it anywhere; the
//  position is remembered.
//

import AppKit
import Defaults

enum BubbleSize: String, CaseIterable, Identifiable, Sendable, Defaults.Serializable {
    case small
    case medium
    case large

    var id: Self { self }

    var diameter: CGFloat {
        switch self {
        case .small: 120
        case .medium: 170
        case .large: 230
        }
    }
}

@MainActor
final class CameraBubbleController {
    private var panel: CameraBubblePanel?

    var isVisible: Bool { panel != nil }

    /// Shows the bubble on `screen`, at its last position when that's still
    /// on this screen, otherwise in the bottom-right corner.
    func show(previewLayer: CALayer, on screen: NSScreen?) {
        hide()
        let diameter = Defaults[.focusBubbleSize].diameter
        let frame = Self.initialFrame(diameter: diameter, screen: screen ?? NSScreen.main)
        let panel = CameraBubblePanel(frame: frame, previewLayer: previewLayer)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.releasePreview()
        panel?.orderOut(nil)
        panel = nil
    }

    private static func initialFrame(diameter: CGFloat, screen: NSScreen?) -> NSRect {
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        if let saved = Defaults[.focusBubbleOrigin], saved.count == 2 {
            let frame = NSRect(x: saved[0], y: saved[1], width: diameter, height: diameter)
            if visible.contains(frame) {
                return frame
            }
        }
        let margin: CGFloat = 24
        return NSRect(
            x: visible.maxX - diameter - margin,
            y: visible.minY + margin,
            width: diameter,
            height: diameter
        )
    }
}

final class CameraBubblePanel: NSPanel, NSWindowDelegate {
    private let hostView: BubbleHostView

    init(frame: NSRect, previewLayer: CALayer) {
        hostView = BubbleHostView(frame: NSRect(origin: .zero, size: frame.size))
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        // sharingType stays at its default on purpose: the bubble must be
        // part of the screen recording.
        contentView = hostView
        hostView.host(previewLayer)
        delegate = self
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func releasePreview() {
        hostView.releaseHostedLayer()
    }

    func windowDidMove(_ notification: Notification) {
        Defaults[.focusBubbleOrigin] = [Double(frame.origin.x), Double(frame.origin.y)]
    }
}

/// Round, bordered host for the camera preview; dragging it moves the window.
final class BubbleHostView: HostedLayerNSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureShape()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureShape()
    }

    override var mouseDownCanMoveWindow: Bool { true }

    override func layout() {
        super.layout()
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
    }

    private func configureShape() {
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
        layer?.masksToBounds = true
        layer?.borderWidth = 3
        layer?.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
        layer?.backgroundColor = NSColor.black.cgColor
    }
}
