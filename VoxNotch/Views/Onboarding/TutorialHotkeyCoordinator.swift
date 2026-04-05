//
//  TutorialHotkeyCoordinator.swift
//  VoxNotch
//
//  Coordinates hotkey detection for the interactive tutorial step.
//  Starts the real dictation pipeline so the notch responds authentically,
//  then wraps HotkeyManager callbacks to also update the tutorial checklist.
//

import Foundation

// MARK: - Checklist Types

enum TutorialChecklistItem: Int, CaseIterable {
  case pressHotkey
  case releaseHotkey
  case modelSwitch
  case toneSwitch
}

enum TutorialItemState {
  case locked
  case active
  case completed
}

// MARK: - Coordinator

@Observable
final class TutorialHotkeyCoordinator {

  // MARK: - Observable State

  var itemStates: [TutorialChecklistItem: TutorialItemState] = [
    .pressHotkey: .active,
    .releaseHotkey: .locked,
    .modelSwitch: .locked,
    .toneSwitch: .locked,
  ]

  var allCompleted = false
  var feedbackText: String?

  // MARK: - Private State

  /// Saved QDC callbacks — forwarded during tutorial so real behavior works
  private var savedOnHotkeyEvent: HotkeyManager.HotkeyCallback?
  private var savedOnModelSwitchKey: ((Int) -> Void)?
  private var savedOnToneSwitchKey: ((Int) -> Void)?
  private var savedOnEscapeKey: (() -> Void)?

  private var isActive = false
  private var currentIndex = 0
  private var feedbackTimer: Timer?

  /// Which tutorial items are available (filtered when no model is downloaded)
  private var availableItems: [TutorialChecklistItem] = TutorialChecklistItem.allCases

  // MARK: - Lifecycle

  func activate(hasModel: Bool = true) {
    guard !isActive else { return }
    isActive = true

    // Filter available items based on whether a model is downloaded
    if hasModel {
      availableItems = TutorialChecklistItem.allCases
    } else {
      availableItems = [.pressHotkey, .releaseHotkey]
    }

    // Reset states for available items
    currentIndex = 0
    itemStates = [:]
    for (index, item) in availableItems.enumerated() {
      itemStates[item] = index == 0 ? .active : .locked
    }
    allCompleted = false

    // Start the full dictation pipeline so the notch responds to hotkey events.
    // These calls are idempotent — safe to call again in startNormalOperation().
    AudioCaptureManager.shared.restoreDeviceSelection()
    AudioCaptureManager.shared.warmUp()
    QuickDictationController.shared.start()

    let hk = HotkeyManager.shared

    // Save QDC's callbacks (just installed by QDC.init or already running)
    savedOnHotkeyEvent = hk.onHotkeyEvent
    savedOnModelSwitchKey = hk.onModelSwitchKey
    savedOnToneSwitchKey = hk.onToneSwitchKey
    savedOnEscapeKey = hk.onEscapeKey

    // Install wrappers: forward to QDC (real behavior) + update checklist
    hk.onHotkeyEvent = { [weak self] event in
      self?.savedOnHotkeyEvent?(event)
      self?.handleHotkeyEvent(event)
    }
    hk.onModelSwitchKey = { [weak self] direction in
      self?.savedOnModelSwitchKey?(direction)
      self?.handleModelSwitch(direction)
    }
    hk.onToneSwitchKey = { [weak self] direction in
      self?.savedOnToneSwitchKey?(direction)
      self?.handleToneSwitch(direction)
    }
    hk.onEscapeKey = savedOnEscapeKey
  }

  func deactivate() {
    guard isActive else { return }
    isActive = false

    let hk = HotkeyManager.shared

    // Restore QDC's original callbacks — QDC stays running
    hk.onHotkeyEvent = savedOnHotkeyEvent
    hk.onModelSwitchKey = savedOnModelSwitchKey
    hk.onToneSwitchKey = savedOnToneSwitchKey
    hk.onEscapeKey = savedOnEscapeKey

    savedOnHotkeyEvent = nil
    savedOnModelSwitchKey = nil
    savedOnToneSwitchKey = nil
    savedOnEscapeKey = nil

    feedbackTimer?.invalidate()
  }

  // MARK: - Event Handlers

  private func handleHotkeyEvent(_ event: HotkeyManager.HotkeyEvent) {
    switch event {
    case .keyDown:
      if currentItem == .pressHotkey {
        completeCurrentItem(feedback: "Recording started — look at the notch!")
      }
    case .keyUp:
      if currentItem == .releaseHotkey {
        completeCurrentItem(feedback: "Transcription triggered!")
      }
    }
  }

  private func handleModelSwitch(_ direction: Int) {
    if currentItem == .modelSwitch {
      completeCurrentItem(feedback: "Model switch — see the notch selector!")
    }
  }

  private func handleToneSwitch(_ direction: Int) {
    if currentItem == .toneSwitch {
      completeCurrentItem(feedback: "Tone switch — you've got it!")
    }
  }

  // MARK: - State Management

  private var currentItem: TutorialChecklistItem? {
    guard currentIndex < availableItems.count else { return nil }
    return availableItems[currentIndex]
  }

  private func completeCurrentItem(feedback: String) {
    guard let item = currentItem else { return }

    itemStates[item] = .completed
    showFeedback(feedback)
    currentIndex += 1

    if currentIndex < availableItems.count {
      itemStates[availableItems[currentIndex]] = .active
    } else {
      allCompleted = true
    }
  }

  private func showFeedback(_ text: String) {
    feedbackText = text
    feedbackTimer?.invalidate()
    feedbackTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
      DispatchQueue.main.async {
        self?.feedbackText = nil
      }
    }
  }
}
