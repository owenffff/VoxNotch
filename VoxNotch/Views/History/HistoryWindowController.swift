//
//  HistoryWindowController.swift
//  VoxNotch
//
//  NSWindowController for managing the History window
//

import AppKit
import SwiftUI

/// Window controller for the History window
@available(macOS 26.0, *)
final class HistoryWindowController: NSWindowController {

  // MARK: - Singleton

  static let shared = HistoryWindowController()

  // MARK: - Initialization

  private init() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )

    window.title = "Transcription History"
    window.center()
    window.minSize = NSSize(width: 650, height: 420)
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: HistoryWindowView())

    /// Restore window position
    window.setFrameAutosaveName("VoxNotchHistoryWindow")
    window.sharingType = SettingsManager.shared.hideFromScreenRecording ? .none : .readOnly

    super.init(window: window)

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleSharingTypeChanged),
      name: .hideFromScreenRecordingChanged,
      object: nil
    )
  }

  // MARK: - Notifications

  @objc private func handleSharingTypeChanged() {
    window?.sharingType = SettingsManager.shared.hideFromScreenRecording ? .none : .readOnly
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - Public Methods

  func show() {
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}
