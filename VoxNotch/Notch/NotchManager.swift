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
    showCompactOrExpand()
  }

  func showTranscribing() {
    cancelAutoHide()
    showCompactOrExpand()
  }

  func showProcessingLLM() {
    cancelAutoHide()
    showCompactOrExpand()
  }

  func showSuccess() {
    cancelAutoHide()
    appState.isShowingSuccess = true
    appState.isShowingClipboard = false
    showCompactOrExpand()
    scheduleAutoHide(after: 1.5)
  }

  func showClipboard() {
    cancelAutoHide()
    appState.isShowingClipboard = true
    appState.isShowingSuccess = false
    showCompactOrExpand()
    scheduleAutoHide(after: 1.5)
  }

  func showError(_ message: String) {
    cancelAutoHide()
    showCompactOrExpand()
    scheduleAutoHide(after: 3.0)
  }

  func showModelSelector() {
    cancelAutoHide()
    showCompactOrExpand()
  }

  func showToneSelector() {
    cancelAutoHide()
    showCompactOrExpand()
  }

  func showModelsNeeded(_ message: String) {
    cancelAutoHide()
    showCompactOrExpand()
  }

  func hide() {
    cancelAutoHide()
    appState.isShowingSuccess = false
    appState.isShowingClipboard = false
    Task {
      await notch?.hide()
    }
  }

  // MARK: - Private

  /// Whether the main screen has a physical notch.
  /// Mirrors DynamicNotchKit's internal `hasNotch` check.
  private var isNotchScreen: Bool {
    guard let screen = NSScreen.main else {
      return false
    }

    return screen.auxiliaryTopLeftArea?.width != nil
      && screen.auxiliaryTopRightArea?.width != nil
  }

  /// On notch Macs, show compact (leading + trailing flanking the notch).
  /// On non-notch Macs, show expanded (floating panel with the same HStack).
  private func showCompactOrExpand() {
    guard
      let notch,
      let screen = NSScreen.main
    else {
      return
    }

    Task {
      if isNotchScreen {
        await notch.compact(on: screen)
      } else {
        await notch.expand(on: screen)
      }
    }
  }

  private func scheduleAutoHide(after seconds: Double) {
    autoHideTask = Task {
      try? await Task.sleep(for: .seconds(seconds))
      guard !Task.isCancelled else { return }
      await notch?.hide()
    }
  }

  private func cancelAutoHide() {
    autoHideTask?.cancel()
    autoHideTask = nil
  }
}
