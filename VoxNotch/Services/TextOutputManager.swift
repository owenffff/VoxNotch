//
//  TextOutputManager.swift
//  VoxNotch
//
//  Text output via CGEvent keystrokes or clipboard paste
//

import Foundation
import AppKit
import Carbon.HIToolbox

/// Manages outputting transcribed text to the active application
final class TextOutputManager {

    // MARK: - Types

    enum TextOutputError: LocalizedError {
        case accessibilityNotGranted
        case noActiveApplication
        case keystrokeFailed
        case clipboardFailed

        var errorDescription: String? {
            switch self {
            case .accessibilityNotGranted:
                return "Accessibility permission required for text output"
            case .noActiveApplication:
                return "No active application to receive text"
            case .keystrokeFailed:
                return "Failed to simulate keystrokes"
            case .clipboardFailed:
                return "Failed to paste from clipboard"
            }
        }
    }

    // MARK: - Properties

    static let shared = TextOutputManager()

    private let keystrokeDelay: TimeInterval = 0.01

    /// Whether to restore clipboard after paste (read from settings)
    var restoreClipboard: Bool {
        SettingsManager.shared.restoreClipboard
    }

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// Output text using clipboard paste or keystroke simulation depending on settings
    /// - Parameter text: The text to output
    func output(_ text: String) async throws {
        if SettingsManager.shared.useClipboardForOutput {
            do {
                try await outputViaClipboard(text)
            } catch {
                try await outputViaKeystrokes(text)
            }
        } else {
            do {
                try await outputViaKeystrokes(text)
            } catch {
                try await outputViaClipboard(text)
            }
        }
    }

    /// Output text via simulated keystrokes
    /// - Parameter text: The text to type
    func outputViaKeystrokes(_ text: String) async throws {
        guard AXIsProcessTrusted() else {
            throw TextOutputError.accessibilityNotGranted
        }

        // Type each character
        for char in text {
            try await typeCharacter(char)
            try await Task.sleep(nanoseconds: UInt64(keystrokeDelay * 1_000_000_000))
        }
    }

    /// Output text via clipboard paste
    /// - Parameter text: The text to paste
    func outputViaClipboard(_ text: String) async throws {
        guard AXIsProcessTrusted() else {
            throw TextOutputError.accessibilityNotGranted
        }

        let pasteboard = NSPasteboard.general

        // Save current clipboard if needed
        var previousContent: String?
        if restoreClipboard {
            previousContent = pasteboard.string(forType: .string)
        }

        // Set new content
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw TextOutputError.clipboardFailed
        }

        // Simulate Cmd+V
        try await simulatePaste()

        // Restore clipboard after a delay
        if let previous = previousContent {
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms delay
            pasteboard.clearContents()
            pasteboard.setString(previous, forType: .string)
        }
    }

    // MARK: - Private Methods

    private func typeCharacter(_ char: Character) async throws {
        guard let eventSource = CGEventSource(stateID: .hidSystemState) else {
            throw TextOutputError.keystrokeFailed
        }

        // Get the string representation
        let string = String(char)

        // Create key events using Unicode approach for reliability
        guard let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: false) else {
            throw TextOutputError.keystrokeFailed
        }

        // Use the Unicode text approach for reliable character input
        var unicodeString = Array(string.utf16)
        keyDown.keyboardSetUnicodeString(stringLength: unicodeString.count, unicodeString: &unicodeString)
        keyUp.keyboardSetUnicodeString(stringLength: unicodeString.count, unicodeString: &unicodeString)

        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
    }

    private func simulatePaste() async throws {
        guard let eventSource = CGEventSource(stateID: .hidSystemState) else {
            throw TextOutputError.keystrokeFailed
        }

        // Key code for 'V' is 9
        let vKeyCode: CGKeyCode = 9

        // Key down with Cmd modifier
        guard let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: eventSource, virtualKey: vKeyCode, keyDown: false) else {
            throw TextOutputError.clipboardFailed
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
    }

    /// Returns true if the frontmost application has a focused text input element.
    func hasFocusedTextInput() -> Bool {
        return hasFocusedTextInput(for: NSWorkspace.shared.frontmostApplication)
    }

    /// Returns true if the given application has a focused text input element.
    /// Uses the Accessibility API to query the focused UI element's role.
    /// When `app` is nil, falls back to the current frontmost application.
    func hasFocusedTextInput(for app: NSRunningApplication?) -> Bool {
        guard let targetApp = app ?? NSWorkspace.shared.frontmostApplication else {
            return false
        }

        // For certain apps like Chrome, Arc, or Electron apps, the accessibility tree
        // might not expose the exact text field role, or it might be an AXWebArea.
        // We can whitelist these apps to always attempt text output.
        if let bundleID = targetApp.bundleIdentifier {
            let whitelistedPrefixes = [
                "com.google.Chrome",
                "company.thebrowser.Browser", // Arc
                "com.microsoft.VSCode",
                "com.tinyspeck.slackmacgap",  // Slack
                "com.hnc.Discord",
                "com.apple.Terminal",
                "com.googlecode.iterm2",
                "com.brave.Browser",
                "com.microsoft.edgemac",       // Edge
                "org.mozilla.firefox",
                "com.microsoft.teams",         // Teams (old & new/teams2)
                "com.anthropic.claudefordesktop", // Claude Desktop
                "md.obsidian",                 // Obsidian
                "us.zoom.xos",                 // Zoom
                "notion.id",                   // Notion
                "com.figma.desktop",           // Figma
                "com.todesktop.230313mzl4w4u92" // Linear
            ]

            if whitelistedPrefixes.contains(where: { bundleID.hasPrefix($0) }) {
                return true
            }
        }

        let pid = targetApp.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        guard result == .success, let element = focusedElement else {
            return false
        }

        let axElement = element as! AXUIElement
        var roleValue: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(axElement, kAXRoleAttribute as CFString, &roleValue)

        guard roleResult == .success, let role = roleValue as? String else {
            return false
        }

        let textRoles: Set<String> = [
            "AXTextField",
            "AXTextArea",
            "AXComboBox",
            "AXSearchField",
            "AXWebArea",
            "AXDocument"
        ]
        return textRoles.contains(role)
    }

    /// Copy text to clipboard without simulating a paste keystroke.
    /// Used as a fallback when no focused text input is detected.
    func copyToClipboardOnly(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Type a specific key with optional modifiers
    /// - Parameters:
    ///   - keyCode: The virtual key code
    ///   - modifiers: Optional modifier flags
    func typeKey(_ keyCode: CGKeyCode, modifiers: CGEventFlags = []) async throws {
        guard let eventSource = CGEventSource(stateID: .hidSystemState) else {
            throw TextOutputError.keystrokeFailed
        }

        guard let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: false) else {
            throw TextOutputError.keystrokeFailed
        }

        if !modifiers.isEmpty {
            keyDown.flags = modifiers
            keyUp.flags = modifiers
        }

        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
    }
}
