//
//  NotchManager.swift
//  VoxNotch
//
//  Owns a persistent NotchPanel and drives expand/collapse via SwiftUI
//  state changes. The panel is created once and never destroyed — only
//  the SwiftUI content inside animates, keeping the window frame fixed.
//

import AppKit
import SwiftUI

// MARK: - Notch State

enum NotchState: Equatable {
  case hidden
  case expanded
}

// MARK: - NotchManager

@MainActor @Observable
final class NotchManager {

  static let shared = NotchManager()

  // MARK: - Observable State

  var notchState: NotchState = .hidden

  /// Physical notch dimensions (or sensible defaults for non-notch Macs).
  var physicalNotchSize: CGSize = CGSize(width: 185, height: 32)

  /// Whether the current display has a physical camera notch.
  var hasPhysicalNotch: Bool = true

  // MARK: - Private

  private var panel: NotchPanel?
  private var autoHideTask: Task<Void, Never>?
  private var orderOutTask: Task<Void, Never>?
  private let appState = AppState.shared

  /// Fixed panel size — large enough for expanded content + shadow padding.
  private static let panelSize = CGSize(width: 640, height: 250)

  private init() {}

  // MARK: - Setup

  func setup() {
    let panel = NotchPanel(
      contentRect: NSRect(origin: .zero, size: Self.panelSize),
      styleMask: [.borderless, .nonactivatingPanel, .utilityWindow],
      backing: .buffered,
      defer: false
    )

    let hostingView = NSHostingView(rootView: NotchContentView())
    hostingView.frame = NSRect(origin: .zero, size: Self.panelSize)
    panel.contentView = hostingView

    self.panel = panel
    detectPhysicalNotch()

    // Reposition when displays change.
    NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        self.detectPhysicalNotch()
        self.repositionPanel()
      }
    }
  }

  // MARK: - Show Methods

  func showRecording() {
    cancelAutoHide()
    showExpanded()
  }

  func showTranscribing() {
    cancelAutoHide()
    showExpanded()
  }

  func showProcessingLLM() {
    cancelAutoHide()
    showExpanded()
  }

  func showSuccess() {
    cancelAutoHide()
    withAnimation(.smooth(duration: 0.4)) {
      appState.isShowingSuccess = true
      appState.isShowingClipboard = false
      appState.isShowingConfirmation = false
    }
    showExpanded()
    scheduleAutoHide(after: 1.5)
  }

  func showClipboard() {
    cancelAutoHide()
    withAnimation(.smooth(duration: 0.4)) {
      appState.isShowingClipboard = true
      appState.isShowingSuccess = false
      appState.isShowingConfirmation = false
    }
    showExpanded()
    scheduleAutoHide(after: 1.5)
  }

  func showError(_ message: String) {
    cancelAutoHide()
    showExpanded()
    scheduleAutoHide(after: 1.5)
  }

  func showModelSelector() {
    cancelAutoHide()
    showExpanded()
  }

  func showToneSelector() {
    cancelAutoHide()
    showExpanded()
  }

  func showModelsNeeded(_ message: String) {
    cancelAutoHide()
    showExpanded()
    scheduleAutoHide(after: 1.5)
  }

  func showConfirmation(_ message: String) {
    cancelAutoHide()
    withAnimation(.smooth(duration: 0.4)) {
      appState.isShowingConfirmation = true
      appState.confirmationMessage = message
      appState.isShowingSuccess = false
      appState.isShowingClipboard = false
    }
    showExpanded()
    scheduleAutoHide(after: 1.5)
  }

  func hide() {
    cancelAutoHide()
    withAnimation(.smooth(duration: 0.4)) {
      appState.isShowingSuccess = false
      appState.isShowingClipboard = false
      appState.isShowingConfirmation = false
    }
    withAnimation(.spring(response: 0.45, dampingFraction: 1.0)) {
      notchState = .hidden
    }
    scheduleOrderOut()
  }

  // MARK: - Private

  /// Show the expanded notch. If already expanded this is a no-op —
  /// content transitions are driven by AppState / displayPhase, not
  /// by re-expanding the panel.
  private func showExpanded() {
    // Cancel any pending orderOut so it can't race with this expand.
    cancelOrderOut()
    ensurePanelVisible()

    guard notchState != .expanded else { return }
    withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
      notchState = .expanded
    }
  }

  private func ensurePanelVisible() {
    guard let panel else { return }
    repositionPanel()
    if !panel.isVisible {
      panel.orderFrontRegardless()
    }
  }

  private func repositionPanel() {
    guard let panel, let screen = NSScreen.main else { return }
    let screenFrame = screen.frame
    let origin = NSPoint(
      x: screenFrame.origin.x + (screenFrame.width - Self.panelSize.width) / 2,
      y: screenFrame.origin.y + screenFrame.height - Self.panelSize.height
    )
    panel.setFrameOrigin(origin)
  }

  /// Detect the physical notch on the main screen and update sizing.
  private func detectPhysicalNotch() {
    guard let screen = NSScreen.main else { return }

    if let topLeft = screen.auxiliaryTopLeftArea?.width,
       let topRight = screen.auxiliaryTopRightArea?.width
    {
      let notchWidth = screen.frame.width - topLeft - topRight
      let notchHeight = screen.safeAreaInsets.top
      hasPhysicalNotch = true
      physicalNotchSize = CGSize(width: notchWidth, height: notchHeight)
    } else {
      hasPhysicalNotch = false
      let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
      physicalNotchSize = CGSize(
        width: 200,
        height: max(menuBarHeight, 24)
      )
    }
  }

  // MARK: - Order Out (tracked, cancellable)

  /// Schedule the panel to be ordered out after the collapse animation.
  private func scheduleOrderOut() {
    cancelOrderOut()
    orderOutTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(0.5))
      guard let self, !Task.isCancelled else { return }
      self.panel?.orderOut(nil)
    }
  }

  private func cancelOrderOut() {
    orderOutTask?.cancel()
    orderOutTask = nil
  }

  // MARK: - Auto Hide

  private func scheduleAutoHide(after seconds: Double) {
    autoHideTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(seconds))
      guard let self, !Task.isCancelled else { return }
      withAnimation(.smooth(duration: 0.4)) {
        self.appState.isShowingSuccess = false
        self.appState.isShowingClipboard = false
        self.appState.isShowingConfirmation = false
        self.appState.lastError = nil
        self.appState.lastErrorRecovery = nil
      }
      withAnimation(.spring(response: 0.45, dampingFraction: 1.0)) {
        self.notchState = .hidden
      }
      self.scheduleOrderOut()
    }
  }

  private func cancelAutoHide() {
    autoHideTask?.cancel()
    autoHideTask = nil
  }
}
