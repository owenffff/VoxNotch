//
//  NotchPanel.swift
//  VoxNotch
//
//  Persistent NSPanel for the notch UI. Created once, never destroyed.
//  Only repositioned via setFrameOrigin — never resized during animation.
//

import Cocoa

final class NotchPanel: NSPanel {

  override init(
    contentRect: NSRect,
    styleMask style: NSWindow.StyleMask,
    backing backingStoreType: NSWindow.BackingStoreType,
    defer flag: Bool
  ) {
    super.init(
      contentRect: contentRect,
      styleMask: style,
      backing: backingStoreType,
      defer: flag
    )

    isFloatingPanel = true
    isOpaque = false
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    backgroundColor = .clear
    isMovable = false

    collectionBehavior = [
      .fullScreenAuxiliary,
      .stationary,
      .canJoinAllSpaces,
      .ignoresCycle,
    ]

    isReleasedWhenClosed = false
    level = .mainMenu + 3
    hasShadow = false
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}
