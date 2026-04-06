//
//  HotkeyRecorderView.swift
//  VoxNotch
//
//  SwiftUI view for recording user hotkey combinations
//

import SwiftUI
import Combine
import Carbon.HIToolbox

/// A view that captures modifier key combinations for hotkey configuration
struct HotkeyRecorderView: View {

  @Binding var displayString: String
  @Binding var modifierFlags: UInt64

  @StateObject private var recorder = HotkeyRecorder()
  @State private var conflictWarning: String?
  @State private var pendingFlags: UInt64?
  @State private var pendingDisplay: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 8) {
        hotkeyDisplay

        if recorder.isRecording {
          Button("Cancel") {
            recorder.stopRecording()
          }
          .buttonStyle(.borderless)
          .foregroundStyle(.secondary)
        } else {
          Button("Change") {
            recorder.startRecording { flags, display in
              /// Check for conflicts before applying
              if let warning = HotkeyConflictDetector.detectConflict(for: flags) {
                conflictWarning = warning
                pendingFlags = flags
                pendingDisplay = display
              } else {
                modifierFlags = flags
                displayString = display
                conflictWarning = nil
              }
            }
          }
          .buttonStyle(.borderless)
        }
      }

      /// Conflict warning
      if let warning = conflictWarning {
        HStack(spacing: 4) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
          Text(warning)
            .font(.caption)
            .foregroundStyle(.orange)
        }
        .padding(.top, 4)

        HStack(spacing: 8) {
          Button("Use Anyway") {
            if let flags = pendingFlags, let display = pendingDisplay {
              modifierFlags = flags
              displayString = display
            }
            conflictWarning = nil
            pendingFlags = nil
            pendingDisplay = nil
          }
          .font(.caption)

          Button("Cancel") {
            conflictWarning = nil
            pendingFlags = nil
            pendingDisplay = nil
          }
          .font(.caption)
          .buttonStyle(.borderless)
        }
      }

      /// Validation error
      if let error = recorder.validationError {
        HStack(alignment: .top, spacing: 4) {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.red)
          Text(error)
            .font(.caption)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
      }
    }
  }

  private var hotkeyDisplay: some View {
    HStack(spacing: 4) {
      if recorder.isRecording {
        Text(recorder.currentKeys.isEmpty ? "Press 2+ modifiers..." : recorder.currentKeys)
          .font(recorder.currentKeys.isEmpty ? .body : .system(size: 14, weight: .medium, design: .rounded))
          .foregroundStyle(recorder.currentKeys.isEmpty ? .secondary : .primary)
          .italic(recorder.currentKeys.isEmpty)
      } else {
        Text(displayString)
          .font(.system(size: 14, weight: .medium, design: .rounded))
      }
    }
    .frame(minWidth: 80)
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(recorder.isRecording ? Color.accentColor.opacity(0.1) : Color(nsColor: .quaternarySystemFill))
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .stroke(recorder.isRecording ? Color.accentColor : Color.clear, lineWidth: 2)
    }
  }
}

// MARK: - Hotkey Recorder Class

/// Observable class to manage hotkey recording state and event monitoring
final class HotkeyRecorder: ObservableObject {

  @Published var isRecording: Bool = false
  @Published var currentKeys: String = ""
  @Published var validationError: String?

  /// Callback when hotkey is captured
  private var onCapture: ((UInt64, String) -> Void)?

  /// Event monitor reference
  private var eventMonitor: Any?

  /// Track the maximum modifiers pressed during the current recording session
  private var maxFlags: NSEvent.ModifierFlags = []

  /// Reserved combinations that shouldn't be used
  private let reservedCombinations: Set<UInt64> = [
    0x100000,  /// Command alone
  ]

  func startRecording(onCapture: @escaping (UInt64, String) -> Void) {
    self.onCapture = onCapture
    isRecording = true
    currentKeys = ""
    validationError = nil
    maxFlags = []
    HotkeyManager.shared.isPaused = true
    setupEventMonitor()
  }

  func stopRecording() {
    isRecording = false
    currentKeys = ""
    maxFlags = []
    HotkeyManager.shared.isPaused = false
    removeEventMonitor()
    onCapture = nil
  }

  private func setupEventMonitor() {
    /// Use local monitor to capture flags changed and key down events
    eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
      self?.handleEvent(event)
      return event
    }
  }

  private func removeEventMonitor() {
    if let monitor = eventMonitor {
      NSEvent.removeMonitor(monitor)
      eventMonitor = nil
    }
  }

  private func handleEvent(_ event: NSEvent) {
    guard isRecording else {
      return
    }

    // If user presses a regular key (like Space, A, 1, etc.), reject it
    if event.type == .keyDown {
      DispatchQueue.main.async { [weak self] in
        self?.validationError = "Please use only modifier keys (Control, Option, Shift, Command). Regular keys are not supported."
        self?.stopRecording()
      }
      return
    }

    guard event.type == .flagsChanged else { return }

    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

    // Update max flags seen during this press
    maxFlags.formUnion(flags)

    // Update UI with currently pressed keys
    DispatchQueue.main.async { [weak self] in
      self?.currentKeys = self?.symbolString(for: flags) ?? ""
    }

    // Only process when all keys are released
    if flags.isEmpty {
      /// Need at least two modifiers for safety
      var count = 0
      if maxFlags.contains(.control) { count += 1 }
      if maxFlags.contains(.option) { count += 1 }
      if maxFlags.contains(.shift) { count += 1 }
      if maxFlags.contains(.command) { count += 1 }

      guard count >= 2 else {
        DispatchQueue.main.async { [weak self] in
          self?.validationError = "Please press at least 2 modifier keys."
          self?.stopRecording()
        }
        return
      }

      /// Convert NSEvent flags to CGEventFlags raw value
      let cgFlags = convertToCGEventFlags(maxFlags)

      /// Check if reserved
      if reservedCombinations.contains(cgFlags) {
        maxFlags = []
        return
      }

      /// Notify callback
      let display = symbolString(for: maxFlags)
      onCapture?(cgFlags, display)

      /// Stop recording
      stopRecording()
    }
  }

  private func convertToCGEventFlags(_ nsFlags: NSEvent.ModifierFlags) -> UInt64 {
    var result: UInt64 = 0

    if nsFlags.contains(.control) {
      result |= CGEventFlags.maskControl.rawValue
    }
    if nsFlags.contains(.option) {
      result |= CGEventFlags.maskAlternate.rawValue
    }
    if nsFlags.contains(.shift) {
      result |= CGEventFlags.maskShift.rawValue
    }
    if nsFlags.contains(.command) {
      result |= CGEventFlags.maskCommand.rawValue
    }

    return result
  }

  private func symbolString(for flags: NSEvent.ModifierFlags) -> String {
    var symbols: [String] = []

    if flags.contains(.control) { symbols.append("\u{2303}") }
    if flags.contains(.option) { symbols.append("\u{2325}") }
    if flags.contains(.shift) { symbols.append("\u{21E7}") }
    if flags.contains(.command) { symbols.append("\u{2318}") }

    return symbols.joined()
  }

  deinit {
    removeEventMonitor()
  }
}

// MARK: - Hotkey Conflict Detector

/// Detects conflicts with known system and common app shortcuts
enum HotkeyConflictDetector {

  /// Known conflicting hotkey combinations and their descriptions
  private static let knownConflicts: [(flags: UInt64, description: String)] = [
    /// System shortcuts (Command-based)
    (CGEventFlags.maskCommand.rawValue, "Cmd alone - reserved by system"),
    (CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue, "Cmd+Shift - may conflict with system shortcuts"),
  ]

  /// Common system shortcuts that conflict
  /// These are modifier-only combinations that may conflict
  private static let systemConflicts: Set<UInt64> = [
    /// Command alone
    CGEventFlags.maskCommand.rawValue,
  ]

  /// Combinations that produce a warning but can still be used
  private static let warningCombinations: [(flags: UInt64, message: String)] = [
    /// Cmd+Shift (used by many apps)
    (
      CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue,
      "\u{2318}\u{21E7} is commonly used by other apps. Consider adding another modifier."
    ),
    /// Cmd+Option (used by accessibility features)
    (
      CGEventFlags.maskCommand.rawValue | CGEventFlags.maskAlternate.rawValue,
      "\u{2318}\u{2325} may conflict with accessibility or app shortcuts."
    ),
    /// Control+Command (used by some apps)
    (
      CGEventFlags.maskCommand.rawValue | CGEventFlags.maskControl.rawValue,
      "\u{2303}\u{2318} may conflict with some app shortcuts."
    ),
    /// All modifiers (complex and may conflict)
    (
      CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue |
      CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue,
      "Using all modifiers may be hard to press consistently."
    ),
  ]

  /// Check if a hotkey combination may conflict with known shortcuts
  /// - Parameter flags: The CGEventFlags raw value to check
  /// - Returns: A warning message if conflict detected, nil otherwise
  static func detectConflict(for flags: UInt64) -> String? {
    /// Check for blocked combinations
    if systemConflicts.contains(flags) {
      return "This combination is reserved by the system."
    }

    /// Check for warning combinations
    for (warningFlags, message) in warningCombinations {
      if flags == warningFlags {
        return message
      }
    }

    return nil
  }
}

// MARK: - Preview

#Preview {
  struct PreviewWrapper: View {
    @State var display = "\u{2303}\u{2325}"
    @State var flags: UInt64 = 0xC0000

    var body: some View {
      HotkeyRecorderView(displayString: $display, modifierFlags: $flags)
        .padding()
    }
  }

  return PreviewWrapper()
}
