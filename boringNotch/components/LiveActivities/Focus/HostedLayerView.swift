//
//  HostedLayerView.swift
//  boringNotch
//
//  SPDX-License-Identifier: GPL-3.0-only
//
//  Shows a layer owned by someone else, such as the recorder's camera
//  preview, without creating anything new on the capture session.
//

import AppKit
import SwiftUI

struct HostedLayerView: NSViewRepresentable {
    let hostedLayer: CALayer

    func makeNSView(context: Context) -> HostedLayerNSView {
        let view = HostedLayerNSView()
        view.host(hostedLayer)
        return view
    }

    func updateNSView(_ nsView: HostedLayerNSView, context: Context) {
        nsView.host(hostedLayer)
    }

    static func dismantleNSView(_ nsView: HostedLayerNSView, coordinator: ()) {
        nsView.releaseHostedLayer()
    }
}

final class HostedLayerNSView: NSView {
    private var hostedLayer: CALayer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // The backing layer must exist before a sublayer is added.
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    func host(_ newLayer: CALayer) {
        guard hostedLayer !== newLayer else { return }
        releaseHostedLayer()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        newLayer.frame = bounds
        layer?.addSublayer(newLayer)
        CATransaction.commit()
        hostedLayer = newLayer
    }

    /// Takes the layer out of this view only; it stays alive (and connected
    /// to its session) for the next view that shows it.
    func releaseHostedLayer() {
        if let hostedLayer, hostedLayer.superlayer === layer {
            hostedLayer.removeFromSuperlayer()
        }
        hostedLayer = nil
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hostedLayer?.frame = bounds
        CATransaction.commit()
    }
}
