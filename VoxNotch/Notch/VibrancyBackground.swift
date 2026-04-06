//
//  VibrancyBackground.swift
//  VoxNotch
//
//  NSViewRepresentable wrapping NSVisualEffectView for behind-window blur.
//

import SwiftUI

struct VibrancyBackground: NSViewRepresentable {

    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
