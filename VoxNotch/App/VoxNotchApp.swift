//
//  VoxNotchApp.swift
//  VoxNotch
//
//  Main entry point for VoxNotch — a notch-native macOS dictation app
//

import SwiftUI

@main
struct VoxNotchApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            EmptyView()
                .frame(width: 0, height: 0)
        }
        .defaultLaunchBehavior(.suppressed)
    }
}
