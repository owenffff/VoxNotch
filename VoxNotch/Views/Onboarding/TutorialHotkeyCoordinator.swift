//
//  TutorialHotkeyCoordinator.swift
//  VoxNotch
//
//  Coordinates hotkey detection for the interactive tutorial step.
//  Temporarily swaps HotkeyManager callbacks, then restores them on dismiss.
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

  private var savedOnHotkeyEvent: HotkeyManager.HotkeyCallback?
  private var savedOnModelSwitchKey: ((Int) -> Void)?
  private var savedOnToneSwitchKey: ((Int) -> Void)?
  private var savedOnEscapeKey: (() -> Void)?

  private var didStartListening = false
  private var isActive = false
  private var currentIndex = 0
  private var feedbackTimer: Timer?

  // MARK: - Lifecycle

  func activate() {
    guard !isActive else { return }
    isActive = true

    let hk = HotkeyManager.shared

    // Save existing callbacks
    savedOnHotkeyEvent = hk.onHotkeyEvent
    savedOnModelSwitchKey = hk.onModelSwitchKey
    savedOnToneSwitchKey = hk.onToneSwitchKey
    savedOnEscapeKey = hk.onEscapeKey

    // Start listening if not already active
    if !hk.isListening {
      didStartListening = hk.startListening()
    }

    // Install tutorial callbacks
    hk.onHotkeyEvent = { [weak self] event in
      self?.handleHotkeyEvent(event)
    }
    hk.onModelSwitchKey = { [weak self] direction in
      self?.handleModelSwitch(direction)
    }
    hk.onToneSwitchKey = { [weak self] direction in
      self?.handleToneSwitch(direction)
    }
    hk.onEscapeKey = nil
  }

  func deactivate() {
    guard isActive else { return }
    isActive = false

    let hk = HotkeyManager.shared

    // Restore saved callbacks
    hk.onHotkeyEvent = savedOnHotkeyEvent
    hk.onModelSwitchKey = savedOnModelSwitchKey
    hk.onToneSwitchKey = savedOnToneSwitchKey
    hk.onEscapeKey = savedOnEscapeKey

    savedOnHotkeyEvent = nil
    savedOnModelSwitchKey = nil
    savedOnToneSwitchKey = nil
    savedOnEscapeKey = nil

    // Stop listening only if we started it
    if didStartListening {
      hk.stopListening()
      didStartListening = false
    }

    feedbackTimer?.invalidate()
  }

  // MARK: - Event Handlers

  private func handleHotkeyEvent(_ event: HotkeyManager.HotkeyEvent) {
    switch event {
    case .keyDown:
      if currentItem == .pressHotkey {
        completeCurrentItem(feedback: "Hotkey detected!")
      }
    case .keyUp:
      if currentItem == .releaseHotkey {
        completeCurrentItem(feedback: "Release detected!")
      }
    }
  }

  private func handleModelSwitch(_ direction: Int) {
    if currentItem == .modelSwitch {
      completeCurrentItem(feedback: "Model switch detected!")
    }
  }

  private func handleToneSwitch(_ direction: Int) {
    if currentItem == .toneSwitch {
      completeCurrentItem(feedback: "Tone switch detected!")
    }
  }

  // MARK: - State Management

  private var currentItem: TutorialChecklistItem? {
    TutorialChecklistItem(rawValue: currentIndex)
  }

  private func completeCurrentItem(feedback: String) {
    guard let item = currentItem else { return }

    itemStates[item] = .completed
    showFeedback(feedback)
    currentIndex += 1

    if let nextItem = TutorialChecklistItem(rawValue: currentIndex) {
      itemStates[nextItem] = .active
    } else {
      allCompleted = true
    }
  }

  private func showFeedback(_ text: String) {
    feedbackText = text
    feedbackTimer?.invalidate()
    feedbackTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
      DispatchQueue.main.async {
        self?.feedbackText = nil
      }
    }
  }
}
