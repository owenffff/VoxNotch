//
//  NotchManager.swift
//  VoxNotch
//
//  Owns the DynamicNotch instance and provides imperative show/hide API.
//  Uses compact mode (leading / trailing) on notch Macs and expanded
//  fallback on non-notch Macs.
//

import AppKit
import DynamicNotchKit
import SwiftUI

@MainActor
final class NotchManager {

  static let shared = NotchManager()

  private var notch: DynamicNotch<
    NotchExpandedFallbackView,
    CompactLeadingView,
    CompactTrailingView
  >?

  private var autoHideTask: Task<Void, Never>?
  private let appState = AppState.shared

  private init() {}

  // MARK: - Setup

  func setup() {
    let expandedView = NotchExpandedFallbackView()
    let leadingView = CompactLeadingView()
    let trailingView = CompactTrailingView()

    notch = DynamicNotch(
      hoverBehavior: [.keepVisible],
      style: .auto,
      expanded: { expandedView },
      compactLeading: { leadingView },
      compactTrailing: { trailingView }
    )
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
    Task {
      await notch?.hide()
    }
  }

  // MARK: - Private

  /// Show the expanded notch (drops below physical notch) for transient messages.
  /// On non-notch Macs, shows the floating panel.
  private func showExpanded() {
    guard
      let notch,
      let screen = NSScreen.main
    else {
      return
    }

    Task {
      await notch.expand(on: screen)
    }
  }

  private func scheduleAutoHide(after seconds: Double) {
    autoHideTask = Task {
      try? await Task.sleep(for: .seconds(seconds))
      guard !Task.isCancelled else { return }
      withAnimation(.smooth(duration: 0.4)) {
        appState.isShowingSuccess = false
        appState.isShowingClipboard = false
        appState.isShowingConfirmation = false
      }
      await notch?.hide()
    }
  }

  private func cancelAutoHide() {
    autoHideTask?.cancel()
    autoHideTask = nil
  }
}
