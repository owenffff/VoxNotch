//
//  OnboardingWindowController.swift
//  VoxNotch
//
//  Window controller for the first-run setup wizard
//

import AppKit
import SwiftUI

final class OnboardingWindowController: NSWindowController {

  // MARK: - Singleton

  static let shared = OnboardingWindowController()

  // MARK: - Properties

  /// Called when onboarding completes (used by AppDelegate to continue startup)
  var onComplete: (() -> Void)?

  // MARK: - Initialization

  private init() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 540, height: 500),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )

    window.title = "Welcome to VoxNotch"
    window.center()
    window.isReleasedWhenClosed = false

    super.init(window: window)

    let onboardingView = OnboardingView {
      SettingsManager.shared.hasCompletedOnboarding = true
      self.onComplete?()
      self.close()
    }
    window.contentView = NSHostingView(rootView: onboardingView)
    window.sharingType = SettingsManager.shared.hideFromScreenRecording ? .none : .readOnly
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - Public

  func show() {
    window?.center()
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}
